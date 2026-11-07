// Σωστές απαντήσεις (με φωνή), παραδείγματα βαθμολόγησης της ΓΔ και αξιολογήσεις AI — μόνο Γενική Διευθύντρια.
//  • Οι σωστές απαντήσεις γράφονται σε ΠΡΟΧΕΙΡΗ έκδοση· ισχύουν μετά την «Ενεργοποίηση», αφού επιβεβαιωθούν οι εκτιμήσεις.
//  • Τα παραδείγματα (βαθμός 0–10 + λόγος σε πραγματικές απαντήσεις) διδάσκουν στο AI πώς βαθμολογεί η ΓΔ.
//  • Οι αξιολογήσεις AI είναι προτάσεις: αλλάζουν βαθμολογία μόνο με «Αποδοχή» ή «Διόρθωση».
import { S } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, confirmBox, norm } from "./util.js";
import * as voice from "./voice.js";

const QTYPE_GR = { single: "Μία επιλογή", multi: "Πολλές επιλογές", scale: "Κλίμακα", text: "Ελεύθερο κείμενο" };
const num = (n) => (n === null || n === undefined || n === "" ? "—" : Number(n).toLocaleString("el-GR", { maximumFractionDigits: 2 }));
const KEY_BADGE = {
  estimate: `<span class="badge b-pending">Κατ' εκτίμηση</span>`,
  confirmed: `<span class="badge b-signed">Επιβεβαιωμένη</span>`,
  excel: `<span class="badge b-info">Από Excel</span>`,
  none: `<span class="badge b-missing">Χωρίς απάντηση</span>`,
};
const keyState = (x) => x.key_status || (x.correct?.length || x.model_answer ? "excel" : "none");
const hasKey = (x) => !!(x.correct?.length || x.model_answer);
const optLabel = (x, k) => x.options.find((o) => o.key === k)?.label || "";
const keyText = (x) => (x.correct?.length ? x.correct.map((k) => `${k}. ${optLabel(x, k)}`).join(" · ") : "");

// ═══════════════════════ Φωνητικός «οδηγός»: ερώτηση → απάντηση → επόμενη ═══════════════════════
const CMD = [
  ["stop", /^(τελος|σταματα|σταματαμε|στοπ|φτανει|εξοδος|τελειωσαμε)(?:\s|$)/],
  ["skip", /^(επομενη|επομενο|παραλειψη|παρακατω|προσπερασε|δεν ξερω|πασο|αστο)(?:\s|$)/],
  ["back", /^(πισω|προηγουμενη|προηγουμενο)(?:\s|$)/],
  ["repeat", /^(επαναλαβε|ξαναπες|ξανα|παλι|τι ειπες|ξαναδιαβασε)(?:\s|$)/],
];
const plain = (t) => norm(t).replace(/[.,;!·]/g, " ").replace(/\s+/g, " ").trim();
function command(t) {
  const p = plain(t);
  if (p.split(" ").length > 4) return null;
  return CMD.find(([, re]) => re.test(p))?.[0] || null;
}

/**
 * items: λίστα · card(item,i) → HTML · say(item,i) → κείμενο για ανάγνωση
 * handle(item, transcript) → { summary (για ανάγνωση), html (αποτέλεσμα), retry (true = ξανά η ίδια) }
 */
function runVoice({ title, items, card, say, handle, onClose }) {
  let i = 0, paused = false, busy = false, closed = false, stopRec = () => {};
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(title)}</div><h2 id="vr-prog"></h2></div><button class="icon-btn" id="vr-x" aria-label="Κλείσιμο">✕</button></div>
    <div id="vr-card" class="vr-card"></div>
    <div class="voice-status" id="vr-stat"></div>
    <div id="vr-live" class="vr-live muted"></div>
    <div id="vr-res"></div>
    <form id="vr-type" class="vr-type"><input id="vr-in" placeholder="…ή γράψτε την απάντηση και πατήστε Enter" autocomplete="off"></form>
    <p class="muted small" style="margin-top:8px">Φωνητικές εντολές: «επόμενη» (παράλειψη), «πίσω», «επανάλαβε», «τέλος».</p>
    <div class="dlg-foot vr-foot">
      <button class="btn" id="vr-back">⏮ Πίσω</button><button class="btn" id="vr-rep">🔁 Επανάληψη</button>
      <button class="btn" id="vr-pause">⏸ Παύση</button><button class="btn" id="vr-skip">⏭ Παράλειψη</button>
      <button class="btn primary" id="vr-done" hidden>✓ Τέλος απάντησης</button>
      <button class="btn danger" id="vr-stop">■ Τέλος</button></div>`, {
    wide: true,
    onOpen(dlg) {
      const status = (html, kind = "") => { $("#vr-stat").className = "voice-status " + kind; $("#vr-stat").innerHTML = html; };
      const finish = () => {
        if (closed) return; closed = true;
        voice.stopListening(); voice.stopSpeaking();
        closeDialog(); onClose?.();
      };
      dlg.addEventListener("close", () => { if (!closed) { closed = true; voice.stopListening(); voice.stopSpeaking(); onClose?.(); } }, { once: true });
      const show = () => {
        $("#vr-prog").textContent = `${i + 1} από ${items.length}`;
        $("#vr-card").innerHTML = card(items[i], i);
        $("#vr-live").textContent = ""; $("#vr-in").value = "";
      };
      const go = (n) => { voice.stopListening(); voice.stopSpeaking(); i = n; if (i >= items.length) return end(); if (i < 0) i = 0; ask(); };
      const end = async () => {
        status("✓ Ολοκληρώθηκαν όλες. Ελέγξτε τα αποτελέσματα στη λίστα.", "");
        await voice.speak("Τελειώσαμε. Ελέγξτε τα αποτελέσματα στη λίστα.");
        finish();
      };
      const listenNow = () => {
        if (closed || paused) return;
        if (!voice.canListen) return status("Η φωνή λειτουργεί σε Chrome ή Edge — γράψτε την απάντηση από κάτω.", "warn");
        status(`<span class="rec-dot"></span> Ακούω… μιλήστε. Όταν τελειώσετε, κάντε μια μικρή παύση ή πατήστε «✓ Τέλος απάντησης».`, "on");
        $("#vr-done").hidden = false;
        stopRec = voice.listen({
          continuous: true, silenceMs: 2600,
          onText: (t) => ($("#vr-live").textContent = t),
          onEnd: (t) => { $("#vr-done").hidden = true; if (closed || paused) return; if (!t) { paused = true; $("#vr-pause").textContent = "▶ Συνέχεια"; return status("Δεν ακούστηκε κάτι — πατήστε «▶ Συνέχεια» όταν είστε έτοιμη.", "warn"); } take(t); },
          onError: (m) => { $("#vr-done").hidden = true; paused = true; $("#vr-pause").textContent = "▶ Συνέχεια"; status(h(m), "bad"); },
        });
      };
      const ask = async () => {
        if (closed) return;
        show(); $("#vr-res").innerHTML = "";
        if (paused) return status("Σε παύση.", "warn");
        status("🔊 Διαβάζω…");
        await voice.speak(say(items[i], i));
        if (!closed && !paused) listenNow();
      };
      const take = async (t) => {
        const c = command(t);
        if (c === "stop") return finish();
        if (c === "skip") return go(i + 1);
        if (c === "back") return go(i - 1);
        if (c === "repeat") return ask();
        busy = true; status("⏳ Καταχωρίζω…");
        try {
          const r = await handle(items[i], t);
          $("#vr-res").innerHTML = r.html || "";
          if (r.retry) { status(h(r.summary || "Δεν κατάλαβα — πείτε το ξανά."), "warn"); await voice.speak(r.summary || "Δεν κατάλαβα. Πείτε το ξανά."); busy = false; return listenNow(); }
          status("✓ " + h(r.summary || "Καταχωρήθηκε."));
          await voice.speak(r.summary || "Καταχωρήθηκε.");
          busy = false;
          if (!closed) go(i + 1);
        } catch (e) { busy = false; paused = true; $("#vr-pause").textContent = "▶ Συνέχεια"; status(h(e.message), "bad"); }
      };
      $("#vr-x").onclick = finish; $("#vr-stop").onclick = finish;
      $("#vr-skip").onclick = () => go(i + 1); $("#vr-back").onclick = () => go(i - 1);
      $("#vr-rep").onclick = () => { paused = false; $("#vr-pause").textContent = "⏸ Παύση"; ask(); };
      $("#vr-done").onclick = () => stopRec();
      $("#vr-pause").onclick = () => {
        paused = !paused; $("#vr-pause").textContent = paused ? "▶ Συνέχεια" : "⏸ Παύση";
        if (paused) { voice.stopListening(); voice.stopSpeaking(); $("#vr-done").hidden = true; status("Σε παύση.", "warn"); } else ask();
      };
      $("#vr-type").onsubmit = (e) => { e.preventDefault(); const t = $("#vr-in").value.trim(); if (!t || busy) return; voice.stopListening(); voice.stopSpeaking(); take(t); };
      ask();
    },
  });
}

// ═══════════════════════ 1. Σωστές απαντήσεις ═══════════════════════
export async function keysTab(q, body, reload) {
  const latest = q.versions[0];
  if (!latest) return (body.innerHTML = `<div class="card empty">Δεν υπάρχουν ερωτήσεις.</div>`);
  const qs = await S.api.questions(latest.id);
  const draft = latest.status === "draft";
  const keyable = qs.filter((x) => x.qtype !== "scale");
  const F = (S.filters.keys ??= { show: "missing", spec: "" });
  const counts = { none: 0, estimate: 0, confirmed: 0, excel: 0 }; keyable.forEach((x) => counts[keyState(x)]++);
  const specs = [...new Set(keyable.map((x) => x.specialty || "Όλες οι ειδικότητες"))];
  const list = keyable.filter((x) => (!F.spec || (x.specialty || "Όλες οι ειδικότητες") === F.spec) && (F.show === "all" || (F.show === "missing" ? !hasKey(x) : F.show === "estimate" ? x.key_status === "estimate" : hasKey(x))));
  const noPoints = keyable.filter((x) => ["single", "multi"].includes(x.qtype) && x.correct?.length && !x.points).length;
  body.innerHTML = `<div class="card">
    <div class="card-head"><h3>Σωστές απαντήσεις</h3><div class="row-actions">
      ${draft ? `<button class="btn primary" id="ky-voice">🎤 Φωνητική συμπλήρωση</button>` : `<button class="btn primary" id="ky-begin">Έναρξη συμπλήρωσης σωστών απαντήσεων</button>`}</div></div>
    <p class="muted small" style="margin:4px 0 12px">Ο Βοηθός διαβάζει κάθε ερώτηση και τις επιλογές· εσείς λέτε τη σωστή απάντηση (π.χ. «το Β» ή, σε ελεύθερο κείμενο, την πρότυπη απάντηση με δικά σας λόγια).
      Το AI την περνά <strong>κατ' εκτίμηση</strong>· μετά τη διορθώνετε ή την επιβεβαιώνετε. Οι κλίμακες αυτοαξιολόγησης δεν έχουν σωστή απάντηση.</p>
    ${draft ? `<div class="note">Οι αλλαγές γράφονται στην <strong>πρόχειρη έκδοση ${latest.version}</strong>. Οι εργαζόμενοι συνεχίζουν με την ενεργή έκδοση μέχρι να πατήσετε
      «Ρυθμίσεις & διαθεσιμότητα → Ενεργοποίηση έκδοσης ${latest.version}», που επιτρέπεται μόνο όταν επιβεβαιωθούν όλες οι εκτιμήσεις.</div>`
      : `<div class="note">Εμφανίζεται η ${latest.status === "published" ? "ενεργή" : "τελευταία"} έκδοση ${latest.version}. Με την «Έναρξη» δημιουργείται πρόχειρη έκδοση ${latest.version + 1} για τις αλλαγές· η ενεργή δεν επηρεάζεται.</div>`}
    <div class="chips" style="margin:12px 0">${[["none", "Χωρίς απάντηση"], ["estimate", "Κατ' εκτίμηση"], ["confirmed", "Επιβεβαιωμένες"], ["excel", "Από Excel"]].map(([k, l]) => `<span class="chip">${l}<span class="n">${counts[k]}</span></span>`).join("")}</div>
    <div class="toolbar">
      <select id="ky-show">${[["missing", "Μόνο όσες λείπουν"], ["estimate", "Κατ' εκτίμηση (προς έλεγχο)"], ["done", "Με απάντηση"], ["all", "Όλες"]].map(([k, l]) => `<option value="${k}" ${F.show === k ? "selected" : ""}>${l}</option>`).join("")}</select>
      ${specs.length > 1 ? `<select id="ky-spec"><option value="">Όλες οι ειδικότητες</option>${specs.map((s) => `<option ${F.spec === s ? "selected" : ""}>${h(s)}</option>`).join("")}</select>` : ""}
      ${draft && counts.estimate ? `<button class="btn" id="ky-confirm-all">✓ Επιβεβαίωση όλων των εκτιμήσεων (${counts.estimate})</button>` : ""}
      ${draft && noPoints ? `<span class="small">Βαθμοί σε ${noPoints} ερωτήσεις επιλογής χωρίς βαθμούς:</span><input id="ky-pts" value="1" inputmode="decimal" style="width:70px"><button class="btn" id="ky-pts-ok">Ορισμός</button>` : ""}
    </div>
    ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>#</th><th>Ερώτηση</th><th>Σωστή / πρότυπη απάντηση</th><th class="r">Βαθμοί</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${list.map((x) => `<tr data-id="${x.id}"><td class="num">${x.row_no}</td>
        <td><span class="sub">${h(x.specialty || "Όλες")} · ${h(x.section)} · ${QTYPE_GR[x.qtype]}</span>${h(x.text)}</td>
        <td class="small">${keyText(x) ? `<strong>${h(keyText(x))}</strong>` : ""}${x.model_answer ? `<div class="key-model">${h(x.model_answer)}</div>` : ""}${!hasKey(x) ? `<span class="muted">—</span>` : ""}
          ${x.key_note ? `<div class="err-txt">⚠ ${h(x.key_note)}</div>` : ""}${x.key_spoken && x.key_status === "estimate" ? `<div class="muted">Είπατε: «${h(x.key_spoken)}»</div>` : ""}</td>
        <td class="r num">${num(x.points)}</td><td>${KEY_BADGE[keyState(x)]}</td>
        <td class="acts" style="white-space:nowrap;text-align:right">${draft ? `${x.key_status === "estimate" ? `<button class="btn sm" data-ok="${x.id}">✓ Σωστό</button>` : ""}<button class="btn sm" data-ed="${x.id}">Διόρθωση</button>` : ""}</td></tr>`).join("")}
    </tbody></table></div>` : `<div class="empty">${F.show === "missing" && keyable.length ? "Όλες οι ερωτήσεις έχουν σωστή απάντηση. 🎉" : "Καμία ερώτηση με αυτά τα φίλτρα."}</div>`}
  </div>`;
  const re = () => keysTab(q, body, reload);
  $("#ky-show").onchange = (e) => { F.show = e.target.value; re(); };
  $("#ky-spec") && ($("#ky-spec").onchange = (e) => { F.spec = e.target.value; re(); });
  $("#ky-begin") && ($("#ky-begin").onclick = async () => {
    try { const r = await S.api.keyBegin(q.id); toast(`Δημιουργήθηκε πρόχειρη έκδοση ${r.version}.`); reload(); } catch (e) { toast(e.message, true); }
  });
  if (!draft) return;
  const byId = Object.fromEntries(qs.map((x) => [x.id, x]));
  $$("[data-ed]").forEach((b) => (b.onclick = () => editKey(byId[b.dataset.ed], re)));
  $$("[data-ok]").forEach((b) => (b.onclick = async () => { try { await S.api.keyConfirm(latest.id, [b.dataset.ok]); re(); } catch (e) { toast(e.message, true); } }));
  $("#ky-confirm-all") && ($("#ky-confirm-all").onclick = async () => {
    if (!(await confirmBox("Επιβεβαίωση όλων", `Θα επιβεβαιωθούν ${counts.estimate} απαντήσεις που πέρασε το AI κατ' εκτίμηση. Τις έχετε ελέγξει;`, { ok: "Επιβεβαίωση" }))) return;
    try { const r = await S.api.keyConfirm(latest.id, null); toast(`Επιβεβαιώθηκαν ${r.confirmed}.`); re(); } catch (e) { toast(e.message, true); }
  });
  $("#ky-pts-ok") && ($("#ky-pts-ok").onclick = async () => {
    try { const r = await S.api.keyPoints(latest.id, Number($("#ky-pts").value.replace(",", "."))); toast(`Ορίστηκαν βαθμοί σε ${r.updated} ερωτήσεις.`); re(); } catch (e) { toast(e.message, true); }
  });
  $("#ky-voice").onclick = () => {
    voice.unlock();
    const items = keyable.filter((x) => (!F.spec || (x.specialty || "Όλες οι ειδικότητες") === F.spec) && (F.show === "all" ? true : F.show === "estimate" ? x.key_status === "estimate" : !hasKey(x)));
    if (!items.length) return toast("Δεν υπάρχουν ερωτήσεις για συμπλήρωση με αυτό το φίλτρο. Επιλέξτε «Όλες» για να τις ξαναπείτε.", true);
    runVoice({
      title: `${q.title} · σωστές απαντήσεις`, items, onClose: re,
      card: (x) => `<div class="eyebrow">${h(x.specialty || "Όλες οι ειδικότητες")} · ${h(x.section)} · ${QTYPE_GR[x.qtype]}</div><div class="vr-q">${h(x.text)}</div>
        ${x.options.length ? `<ol class="vr-opts">${x.options.map((o) => `<li><strong>${o.key}.</strong> ${h(o.label)}</li>`).join("")}</ol>` : `<p class="muted">Πείτε την πρότυπη απάντηση με δικά σας λόγια.</p>`}
        ${hasKey(x) ? `<p class="small muted">Τωρινή: ${h(keyText(x) || x.model_answer)}</p>` : ""}`,
      say: (x, i) => `Ερώτηση ${i + 1}. ${x.text}. ${x.options.length ? `Επιλογές: ${x.options.map((o) => `${o.key}: ${o.label}`).join(". ")}. ${x.qtype === "multi" ? "Μπορεί να είναι περισσότερες από μία." : ""} Ποια είναι η σωστή;` : "Πείτε την πρότυπη απάντηση."}`,
      handle: async (x, t) => {
        const r = await S.api.aiKey({ mode: "key", question_id: x.id, spoken: t });
        if (["single", "multi"].includes(x.qtype) && !r.correct) return { retry: true, summary: r.note || "Δεν κατάλαβα ποια επιλογή είναι σωστή. Πείτε το ξανά, π.χ. «το Β».", html: `<div class="note warn">Είπατε: «${h(t)}»</div>` };
        await S.api.keySave(x.id, r.correct, r.model_answer, x.points, "estimate", t, r.note || (r.confidence === "low" ? "Χαμηλή βεβαιότητα του AI — ελέγξτε." : null));
        x.correct = r.correct; x.model_answer = r.model_answer; x.key_status = "estimate";
        return { summary: r.spoken_summary || "Καταχωρήθηκε.", html: `<div class="note">Καταχωρήθηκε κατ' εκτίμηση: <strong>${h(keyText(x) || "")}</strong>${r.model_answer ? `<div class="key-model">${h(r.model_answer)}</div>` : ""}${r.note ? `<div class="err-txt">⚠ ${h(r.note)}</div>` : ""}</div>` };
      },
    });
  };
}

function editKey(x, done) {
  const choice = ["single", "multi"].includes(x.qtype);
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">Γραμμή ${x.row_no} · ${QTYPE_GR[x.qtype]}</div><h2>Σωστή απάντηση</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p style="font-weight:600">${h(x.text)}</p>
    ${choice ? `<label>Σωστή επιλογή${x.qtype === "multi" ? " (μία ή περισσότερες)" : ""}</label>${x.options.map((o) => `<label class="check"><input type="${x.qtype === "single" ? "radio" : "checkbox"}" name="ek-c" value="${o.key}" ${(x.correct || []).includes(o.key) ? "checked" : ""}> <strong>${o.key}.</strong> ${h(o.label)}</label>`).join("")}` : ""}
    <label>${choice ? "Αιτιολόγηση (προαιρετικά)" : "Πρότυπη απάντηση"}</label><textarea id="ek-m" rows="5" maxlength="4000">${h(x.model_answer || "")}</textarea>
    ${x.qtype !== "scale" ? `<label>Βαθμοί ${choice ? "(χωρίς βαθμούς η ερώτηση δείχνει σωστό/λάθος αλλά δεν μετρά στο σύνολο)" : "(ελεύθερο κείμενο: βαθμολογείται χειροκίνητα ή με «Αξιολογήσεις AI»)"}</label><input id="ek-p" inputmode="decimal" value="${x.points ?? ""}" style="width:110px">` : ""}
    ${x.key_spoken ? `<p class="muted small">Είπατε: «${h(x.key_spoken)}»</p>` : ""}${x.key_note ? `<p class="err-txt small">⚠ ${h(x.key_note)}</p>` : ""}
    <p id="ek-msg" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="ek-ok">Αποθήκευση και επιβεβαίωση</button></div>`, {
    onOpen() {
      $("#ek-ok").onclick = async () => {
        const c = $$('input[name="ek-c"]:checked').map((i) => i.value);
        const p = $("#ek-p") ? $("#ek-p").value.trim().replace(",", ".") : "";
        try { await S.api.keySave(x.id, c.length ? c : null, $("#ek-m").value, p === "" ? (x.qtype === "scale" ? x.points : null) : Number(p), "confirmed"); closeDialog(); toast("Αποθηκεύτηκε."); done(); }
        catch (e) { $("#ek-msg").textContent = e.message; }
      };
    },
  });
}

// ═══════════════════════ 2. Παραδείγματα βαθμολόγησης ═══════════════════════
const groupByQuestion = (rows) => {
  const g = new Map();
  for (const r of rows) { const k = r.question_id; if (!g.has(k)) g.set(k, { ...r, answers: [] }); g.get(k).answers.push(r); }
  return [...g.values()];
};

export async function examplesTab(q, body, reload) {
  const rows = await S.api.exAnswers(q.id);
  const F = (S.filters.ex ??= { q: "", show: "todo" });
  const groups = groupByQuestion(rows);
  const rated = rows.filter((r) => r.example_id).length;
  body.innerHTML = `<div class="card">
    <div class="card-head"><h3>Παραδείγματα βαθμολόγησης</h3><div class="row-actions">${rows.length ? `<button class="btn primary" id="ex-voice">🎤 Βαθμολόγηση με φωνή</button>` : ""}</div></div>
    <p class="muted small" style="margin:4px 0 12px">Ο Βοηθός σάς διαβάζει την ερώτηση και την απάντηση ενός εργαζομένου (χωρίς όνομα). Λέτε βαθμό <strong>0 έως 10</strong> και τον λόγο
      — τι ήταν σωστό, τι έλειπε, τι δεν πρέπει να λέγεται. Έτσι το AI μαθαίνει πώς βαθμολογείτε και πόσο αξίζει κάθε απάντηση. Ισχύει για ερωτήσεις ελεύθερου κειμένου.</p>
    ${rows.length ? `<div class="chips" style="margin-bottom:12px"><span class="chip">Απαντήσεις<span class="n">${rows.length}</span></span><span class="chip">Με βαθμό σας<span class="n">${rated}</span></span><span class="chip">Ερωτήσεις<span class="n">${groups.length}</span></span></div>
    <div class="toolbar"><select id="ex-q"><option value="">Όλες οι ερωτήσεις</option>${groups.map((g) => `<option value="${g.question_id}" ${F.q === g.question_id ? "selected" : ""}>${h(g.row_no + ". " + g.question_text.slice(0, 70))}${g.version > 1 ? ` (έκδ. ${g.version})` : ""}</option>`).join("")}</select>
      <select id="ex-show"><option value="todo" ${F.show === "todo" ? "selected" : ""}>Χωρίς βαθμό σας</option><option value="done" ${F.show === "done" ? "selected" : ""}>Με βαθμό σας</option><option value="all" ${F.show === "all" ? "selected" : ""}>Όλες</option></select></div>
    ${groups.filter((g) => !F.q || g.question_id === F.q).map((g) => { const ans = g.answers.filter((a) => F.show === "all" || (F.show === "done" ? a.example_id : !a.example_id)); return ans.length ? `
      <div class="ex-group"><div class="ex-q"><span class="muted">${g.row_no}. ${h(g.section)}${g.version > 1 ? ` · έκδ. ${g.version}` : ""}</span><br><strong>${h(g.question_text)}</strong>
        ${g.model_answer ? `<div class="key-model"><span class="muted">Σωστή απάντηση:</span> ${h(g.model_answer)}</div>` : `<div class="muted small">Δεν έχει οριστεί σωστή απάντηση (καρτέλα «Σωστές απαντήσεις»).</div>`}</div>
        ${ans.map((a) => `<div class="ex-row" data-k="${a.attempt_id}|${a.question_id}">
          <div class="ex-ans"><span class="muted small">${h(a.employee_name)} · ${h(a.store)}</span><div>${h(a.answer_text)}</div>${a.eval_id ? `<div class="muted small">AI: ${num(a.eval_score)}/10 — ${h(a.eval_reason)}</div>` : ""}</div>
          <div class="ex-rate"><input class="ex-s" inputmode="decimal" placeholder="0–10" value="${a.example_score ?? ""}"><textarea class="ex-r" rows="2" placeholder="Λόγος: τι ήταν καλό, τι έλειπε, τι δεν πρέπει να λέγεται">${h(a.example_reason || "")}</textarea>
            <div class="row-actions"><button class="btn sm primary ex-save">Αποθήκευση</button>${a.example_id ? `<button class="btn sm ex-del" data-id="${a.example_id}">Αφαίρεση</button>` : ""}</div></div></div>`).join("")}</div>` : ""; }).join("") || `<div class="empty">Καμία απάντηση με αυτά τα φίλτρα.</div>`}`
    : `<div class="empty"><div class="big">💬</div>Δεν υπάρχουν ακόμη υποβληθείσες απαντήσεις ελεύθερου κειμένου σε αυτό το ερωτηματολόγιο.</div>`}
  </div>`;
  if (!rows.length) return;
  const re = () => examplesTab(q, body, reload);
  $("#ex-q").onchange = (e) => { F.q = e.target.value; re(); };
  $("#ex-show").onchange = (e) => { F.show = e.target.value; re(); };
  $$(".ex-row").forEach((el) => {
    const [att, qid] = el.dataset.k.split("|");
    $(".ex-save", el).onclick = async () => {
      const s = Number($(".ex-s", el).value.replace(",", "."));
      if ($(".ex-s", el).value.trim() === "" || !(s >= 0 && s <= 10)) return toast("Βαθμός από 0 έως 10.", true);
      try { await S.api.exSave(att, qid, s, $(".ex-r", el).value, null, "typed"); toast("Αποθηκεύτηκε."); re(); } catch (e) { toast(e.message, true); }
    };
    $(".ex-del", el) && ($(".ex-del", el).onclick = async () => { try { await S.api.exDelete($(".ex-del", el).dataset.id); re(); } catch (e) { toast(e.message, true); } });
  });
  $("#ex-voice").onclick = () => {
    voice.unlock();
    const items = rows.filter((r) => (!F.q || r.question_id === F.q) && (F.show === "all" || (F.show === "done" ? r.example_id : !r.example_id)));
    if (!items.length) return toast("Δεν υπάρχουν απαντήσεις με αυτά τα φίλτρα.", true);
    runVoice({
      title: `${q.title} · παραδείγματα βαθμολόγησης`, items, onClose: re,
      card: (a) => `<div class="eyebrow">${h(a.section)} · ερώτηση ${a.row_no}</div><div class="vr-q">${h(a.question_text)}</div>
        ${a.model_answer ? `<div class="key-model"><span class="muted">Σωστή απάντηση:</span> ${h(a.model_answer)}</div>` : ""}
        <div class="vr-ans"><span class="muted small">Απάντηση εργαζομένου</span><div>${h(a.answer_text)}</div></div>`,
      say: (a, i) => `${i === 0 || items[i - 1].question_id !== a.question_id ? `Ερώτηση: ${a.question_text}. ` : ""}Απάντηση εργαζομένου: ${a.answer_text}. Τι βαθμό δίνετε από 0 έως 10, και γιατί;`,
      handle: async (a, t) => {
        const r = await S.api.aiKey({ mode: "rate", question_id: a.question_id, answer: a.answer_text, spoken: t });
        if (r.score === null || r.score === undefined) return { retry: true, summary: "Δεν άκουσα βαθμό. Πείτε έναν αριθμό από 0 έως 10 και τον λόγο.", html: `<div class="note warn">Είπατε: «${h(t)}»</div>` };
        await S.api.exSave(a.attempt_id, a.question_id, r.score, r.reason, t, "voice");
        a.example_id = "x"; a.example_score = r.score; a.example_reason = r.reason;
        return { summary: r.spoken_summary || `${r.score}. Καταχωρήθηκε.`, html: `<div class="note">Καταχωρήθηκε: <strong>${num(r.score)}/10</strong> — ${h(r.reason)}</div>` };
      },
    });
  };
}

// ═══════════════════════ 3. Αξιολογήσεις AI ═══════════════════════
const EV_BADGE = { suggested: `<span class="badge b-info">Πρόταση AI</span>`, accepted: `<span class="badge b-signed">Αποδεκτή</span>`, corrected: `<span class="badge b-signed">Διορθώθηκε</span>`, rejected: `<span class="badge b-voided">Απορρίφθηκε</span>` };

export async function evalsTab(q, body, reload) {
  const rows = await S.api.exAnswers(q.id);
  const groups = groupByQuestion(rows);
  const exCount = await Promise.all(groups.map((g) => S.api.exForQuestion(g.question_id).then((x) => x.length).catch(() => 0)));
  const F = (S.filters.ev ??= { q: "", show: "open" });
  const todo = (g) => g.answers.filter((a) => !a.example_id && (!a.eval_id || a.eval_status === "suggested"));
  // Πόσο συμφωνεί το AI μαζί σας: απαντήσεις που διορθώσατε ή αποδεχτήκατε
  const reviewed = rows.filter((a) => ["accepted", "corrected"].includes(a.eval_status));
  const diff = reviewed.length ? reviewed.reduce((s, a) => s + Math.abs(Number(a.eval_score) - Number(a.eval_final)), 0) / reviewed.length : null;
  body.innerHTML = `<div class="card">
    <div class="card-head"><h3>Αξιολογήσεις AI</h3><div class="row-actions">${groups.length ? `<button class="btn primary" id="ev-all">✦ Αξιολόγηση όλων με AI</button>` : ""}</div></div>
    <p class="muted small" style="margin:4px 0 12px">Το AI προτείνει βαθμό 0–10 και αιτιολογία για κάθε απάντηση ελεύθερου κειμένου, με βάση τη <strong>σωστή απάντηση</strong> και τα <strong>παραδείγματα βαθμολόγησής σας</strong>.
      Τίποτα δεν αλλάζει στη βαθμολογία μέχρι να πατήσετε «Αποδοχή» ή «Διόρθωση». Κάθε διόρθωση γίνεται νέο παράδειγμα, οπότε το AI βελτιώνεται.
      Αν η ερώτηση έχει βαθμούς, ο βαθμός περνά αναλογικά (π.χ. 7/10 σε ερώτηση 2 βαθμών = 1,4).</p>
    ${reviewed.length ? `<div class="note" style="margin-bottom:12px">Ακρίβεια μέχρι τώρα: σε ${reviewed.length} απαντήσεις που ελέγξατε, το AI απείχε κατά μέσο όρο <strong>${num(diff)}</strong> μονάδες από τον δικό σας βαθμό.</div>` : ""}
    ${groups.length ? `<div class="toolbar"><select id="ev-q"><option value="">Όλες οι ερωτήσεις</option>${groups.map((g) => `<option value="${g.question_id}" ${F.q === g.question_id ? "selected" : ""}>${h(g.row_no + ". " + g.question_text.slice(0, 70))}</option>`).join("")}</select>
      <select id="ev-show"><option value="open" ${F.show === "open" ? "selected" : ""}>Προς έλεγχο</option><option value="all" ${F.show === "all" ? "selected" : ""}>Όλες</option></select></div>
    ${groups.map((g, gi) => (F.q && g.question_id !== F.q ? "" : `<div class="ex-group">
      <div class="ex-q" style="display:flex;gap:12px;align-items:flex-start"><div style="flex:1"><span class="muted">${g.row_no}. ${h(g.section)}${g.version > 1 ? ` · έκδ. ${g.version}` : ""}${g.points ? ` · ${num(g.points)} βαθμοί` : " · χωρίς βαθμούς"}</span><br><strong>${h(g.question_text)}</strong>
        <div class="small muted">${g.model_answer ? "✓ σωστή απάντηση" : "✗ χωρίς σωστή απάντηση"} · ${exCount[gi]} παραδείγματα βαθμολόγησης</div></div>
        <button class="btn sm" data-evq="${g.question_id}" ${!g.model_answer && !exCount[gi] ? `disabled title="Χρειάζεται σωστή απάντηση ή παραδείγματα"` : ""}>✦ Αξιολόγηση (${todo(g).length})</button></div>
      ${g.answers.filter((a) => F.show === "all" || (a.eval_id && a.eval_status === "suggested")).map((a) => `<div class="ex-row">
        <div class="ex-ans"><span class="muted small">${h(a.employee_name)} · ${h(a.store)}</span><div>${h(a.answer_text)}</div>
          ${a.example_id ? `<div class="small"><strong>Δικός σας βαθμός: ${num(a.example_score)}/10</strong> ${a.example_reason ? "— " + h(a.example_reason) : ""}</div>` : ""}</div>
        <div class="ex-rate">${a.eval_id ? `<div><span class="ev-score">${num(a.eval_status === "corrected" ? a.eval_final : a.eval_score)}/10</span> ${EV_BADGE[a.eval_status]}</div><div class="small">${h(a.eval_reason)}</div>
          ${a.eval_status === "corrected" ? `<div class="small muted">Πρόταση AI: ${num(a.eval_score)}/10</div>` : ""}
          ${a.max_points ? `<div class="small muted">Βαθμολογία: ${a.graded_at ? `${num(a.grade_points)} / ${num(a.max_points)}` : `εκκρεμεί (έως ${num(a.max_points)})`}</div>` : ""}
          ${a.eval_status === "suggested" ? `<div class="row-actions"><button class="btn sm primary" data-acc="${a.eval_id}">Αποδοχή</button><button class="btn sm" data-cor="${a.eval_id}" data-s="${a.eval_score}">Διόρθωση</button><button class="btn sm danger" data-rej="${a.eval_id}">Απόρριψη</button></div>` : ""}`
          : a.example_id ? `<span class="muted small">Βαθμολογήθηκε από εσάς — δεν χρειάζεται AI.</span>` : `<span class="muted small">Δεν έχει αξιολογηθεί ακόμη.</span>`}</div></div>`).join("")}</div>`)).join("")}`
    : `<div class="empty"><div class="big">✦</div>Δεν υπάρχουν ακόμη υποβληθείσες απαντήσεις ελεύθερου κειμένου σε αυτό το ερωτηματολόγιο.</div>`}
  </div>`;
  if (!groups.length) return;
  const re = () => evalsTab(q, body, reload);
  $("#ev-q").onchange = (e) => { F.q = e.target.value; re(); };
  $("#ev-show").onchange = (e) => { F.show = e.target.value; re(); };
  const runFor = async (g) => {
    const items = todo(g).map((a) => ({ attempt_id: a.attempt_id, answer: a.answer_text }));
    let n = 0;
    for (let k = 0; k < items.length; k += 20) {
      const part = items.slice(k, k + 20);
      const r = await S.api.aiKey({ mode: "evaluate", question_id: g.question_id, items: part });
      await S.api.evSave(g.question_id, r.items, r.examples_used, r.model);
      n += r.items.length;
    }
    return n;
  };
  const busy = (b, on) => { b.disabled = on; if (on) { b.dataset.t = b.textContent; b.textContent = "⏳ Αξιολόγηση…"; } else b.textContent = b.dataset.t; };
  $$("[data-evq]").forEach((b) => (b.onclick = async () => {
    const g = groups.find((x) => x.question_id === b.dataset.evq);
    if (!todo(g).length) return toast("Δεν υπάρχουν απαντήσεις προς αξιολόγηση σε αυτή την ερώτηση.");
    busy(b, true);
    try { const n = await runFor(g); toast(`Το AI αξιολόγησε ${n} απαντήσεις.`); F.show = "open"; re(); } catch (e) { busy(b, false); toast(e.message, true); }
  }));
  $("#ev-all").onclick = async (ev) => {
    const b = ev.currentTarget; busy(b, true); let n = 0; const skipped = [];
    for (const [gi, g] of groups.entries()) {
      if (!todo(g).length) continue;
      if (!g.model_answer && !exCount[gi]) { skipped.push(g.row_no); continue; }
      try { n += await runFor(g); } catch (e) { toast(e.message, true); }
    }
    toast(`Το AI αξιολόγησε ${n} απαντήσεις.${skipped.length ? ` Παραλείφθηκαν ερωτήσεις χωρίς σωστή απάντηση/παραδείγματα: ${skipped.join(", ")}.` : ""}`);
    F.show = "open"; re();
  };
  const review = async (id, action, score, reason) => {
    try { const r = await S.api.evReview(id, action, score, reason); toast(action === "reject" ? "Απορρίφθηκε." : r.applied ? `Καταχωρήθηκε: ${num(r.points)} / ${num(r.max_points)} βαθμοί.` : "Καταχωρήθηκε."); re(); }
    catch (e) { toast(e.message, true); }
  };
  $$("[data-acc]").forEach((b) => (b.onclick = () => review(b.dataset.acc, "accept")));
  $$("[data-rej]").forEach((b) => (b.onclick = () => review(b.dataset.rej, "reject")));
  $$("[data-cor]").forEach((b) => (b.onclick = () => {
    openDialog(`<div class="dlg-head"><h2>Διόρθωση βαθμού</h2><button class="icon-btn" data-close>✕</button></div>
      <p class="muted small">Ο βαθμός σας και ο λόγος γίνονται νέο παράδειγμα βαθμολόγησης, ώστε το AI να μάθει.</p>
      <label>Βαθμός 0–10 (πρόταση AI: ${num(b.dataset.s)})</label><input id="ec-s" inputmode="decimal" style="width:110px">
      <label>Λόγος</label><textarea id="ec-r" rows="3" placeholder="Τι ήταν καλό, τι έλειπε, τι δεν πρέπει να λέγεται"></textarea>
      <p id="ec-m" class="form-msg"></p><div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="ec-ok">Αποθήκευση</button></div>`, {
      onOpen() {
        $("#ec-s").focus();
        $("#ec-ok").onclick = async () => {
          const s = Number($("#ec-s").value.replace(",", "."));
          if ($("#ec-s").value.trim() === "" || !(s >= 0 && s <= 10)) return ($("#ec-m").textContent = "Βαθμός από 0 έως 10.");
          closeDialog(); review(b.dataset.cor, "correct", s, $("#ec-r").value);
        };
      },
    });
  }));
}
