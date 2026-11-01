// Απομονωμένη οθόνη εργαζομένου (χωρίς λογαριασμό).
// Δεν φορτώνει ΤΙΠΟΤΑ από την υπόλοιπη εφαρμογή: η συσκευή έχει αποσυνδεθεί και κρατά μόνο ένα κλειδί μίας χρήσης,
// που ο server δέχεται για μία φόρμα ενός εργαζομένου. Σωστές απαντήσεις και βαθμοί δεν έρχονται ποτέ εδώ.
import { createFillApi } from "./api-supabase.js";

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const h = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const dmy = (iso) => (iso ? String(iso).slice(0, 10).split("-").reverse().join("/") : "");
const athens = (ts) => new Date(ts).toLocaleString("el-GR", { timeZone: "Europe/Athens", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const render = (body, vars) => String(body || "").replace(/\{([^{}\s]+)\}/g, (m, k) => (vars[k] ? String(vars[k]) : m));
const MIMES = { pdf: "application/pdf", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", heic: "image/heic" };

export async function bootFill(cfg, state) {
  document.title = "MEGA GYM · Φόρμα εργαζομένου";
  $("#boot").hidden = true; $("#app").hidden = true; $("#login").hidden = true;
  const root = $("#fill"); root.hidden = false;
  const api = await createFillApi({ url: cfg.supabaseUrl, anonKey: cfg.supabaseAnonKey });
  const T = state.token;
  const head = (sub) => `<div class="k-head"><img src="mega-gym-logo.png" alt="MEGA GYM"><div class="k-title"><strong>Φόρμα εργαζομένου</strong><span>${h(sub || state.label || "")}</span></div><button class="btn" id="f-back">Επιστροφή (υπεύθυνος)</button></div>`;
  const shell = (sub, inner) => { root.innerHTML = head(sub) + `<div class="k-body"><div class="k-sign">${inner}</div></div>`; $("#f-back").onclick = backToAdmin; };
  const msg = (title, text, ok = false) => shell("", `<div class="k-done">${ok ? `<div class="tick">✓</div>` : ""}<h1 style="font-size:28px">${h(title)}</h1><p class="muted" style="font-size:17px;margin-top:8px">${h(text)}</p><p class="muted" style="margin-top:22px">Παραδώστε τη συσκευή στον υπεύθυνο.</p></div>`);

  function backToAdmin() {
    root.innerHTML = head("Μόνο για τον εξουσιοδοτημένο χρήστη") + `<div class="k-body"><form class="k-sign" style="max-width:440px" id="f-login" autocomplete="off">
      <h2>Επιστροφή στη διαχείριση</h2><p class="muted">Η φόρμα θα κλείσει. Απαιτείται είσοδος με τον κωδικό σας.</p>
      <label>Email</label><input id="fl-e" type="email" value="${h(state.openedBy || "")}" required>
      <label>Κωδικός</label><input id="fl-p" type="password" autocomplete="current-password" required>
      <p id="fl-m" class="form-msg"></p>
      <div class="k-actions"><button type="button" class="btn" id="fl-cancel">Πίσω στη φόρμα</button><button class="btn primary">Είσοδος</button></div></form></div>`;
    $("#f-back").hidden = true;
    $("#fl-p").focus();
    $("#fl-cancel").onclick = () => start();
    $("#f-login").onsubmit = async (e) => {
      e.preventDefault();
      try {
        await api.signIn($("#fl-e").value, $("#fl-p").value);
        sessionStorage.removeItem("mg-fill");
        sessionStorage.setItem("mg-fill-return", JSON.stringify({ sessionId: state.sessionId, kind: state.kind }));
        history.replaceState(null, "", location.pathname + (state.returnTo || "#/"));
        location.reload();
      } catch (err) { $("#fl-m").textContent = err.message; }
    };
  }

  async function start() {
    root.innerHTML = head() + `<div class="k-body"><div class="spinner"></div></div>`;
    $("#f-back").onclick = backToAdmin;
    let d;
    try { d = await api.get(T); }
    catch (e) { return msg("Η φόρμα δεν είναι διαθέσιμη", e.message); }
    if (d.completed) return msg("Η φόρμα έχει ολοκληρωθεί", state.kind === "assessment" ? "Η αξιολόγηση έχει υποβληθεί." : "Το αίτημα έχει ολοκληρωθεί και περιμένει τον έλεγχο του manager.", true);
    if (d.kind === "request") return requestForm(d);
    return assessmentIntro(d);
  }

  // ─────────── Αίτημα ───────────
  function requestForm(d) {
    const f = d.fields || {}, isLeave = d.category === "leave";
    const tpl = d.templates || {};
    let edited = !!f.body, saveTimer;
    shell(`${d.employee.name} · ${d.employee.store}`, `
      <div class="eyebrow">${h(d.ref)} · ${h(d.category_label)}</div><h2 style="font-size:24px">${h(d.employee.name)}</h2>
      <p class="muted">Κωδικός ${h(d.employee.code)} · ${h(d.employee.store)} · ${h(d.employee.company)}</p>
      ${isLeave ? `
        <div class="grid g2"><div><label>Είδος άδειας</label><select id="ff-lt"><option value="">— επιλέξτε —</option>${d.leave_types.map((x) => `<option value="${x.code}" ${x.code === f.leave_type ? "selected" : ""}>${h(x.label)}</option>`).join("")}</select></div>
          <div><label>Ημέρες άδειας που αιτείστε</label><input id="ff-days" inputmode="decimal" value="${h(f.days_requested ?? "")}"></div>
          <div><label>Από</label><input type="date" id="ff-s" value="${h(f.start_date || "")}"></div><div><label>Έως και</label><input type="date" id="ff-e" value="${h(f.end_date || "")}"></div></div>
        <p id="ff-cal" class="muted small" style="margin-top:8px"></p>
        <div class="statement small">${h(tpl.leave_request_help?.body || "")}</div>
        <label>Κείμενο αίτησης</label><textarea id="ff-body" rows="4" maxlength="8000">${h(f.body || "")}</textarea>
        <label>Παρατηρήσεις (προαιρετικά)</label><textarea id="ff-notes" rows="2" maxlength="4000">${h(f.details?.notes || "")}</textarea>`
      : `<label>Θέμα</label><input id="ff-subj" maxlength="200" value="${h(f.details?.subject || "")}">
        <label>Το αίτημά σας</label><textarea id="ff-body" rows="7" maxlength="8000">${h(f.body || "")}</textarea>`}
      <label>Δικαιολογητικά (προαιρετικά · PDF ή φωτογραφία έως 4 MB)</label><input type="file" id="ff-file" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic">
      <p class="muted small" id="ff-att">${d.attachments.length ? "Επισυνάφθηκαν: " + d.attachments.map((a) => h(a.filename)).join(", ") : ""}</p>
      <p id="ff-m" class="form-msg"></p><p id="ff-saved" class="muted small"></p>
      <div class="k-actions"><button class="btn primary" id="ff-done">Ολοκλήρωση</button></div>
      <p class="muted small" style="margin-top:12px">Η υποβολή δεν αποτελεί έγκριση. Ο manager θα ελέγξει και θα υποβάλει το αίτημα· η απόφαση θα σας γνωστοποιηθεί μέσω του manager του καταστήματός σας.</p>`);
    const val = (id) => $("#" + id)?.value?.trim() ?? "";
    const regen = () => {
      if (!isLeave) return;
      const a = val("ff-s"), b = val("ff-e");
      const cal = a && b && b >= a ? Math.round((Date.parse(b) - Date.parse(a)) / 86400000) + 1 : null;
      $("#ff-cal").textContent = cal ? `Ημερολογιακές ημέρες: ${cal}. Δεν ταυτίζονται απαραίτητα με τις ημέρες άδειας σύμφωνα με το πρόγραμμά σας.` : "";
      if (!edited) $("#ff-body").value = render(tpl.leave_request_body?.body, { είδος_άδειας: d.leave_types.find((x) => x.code === val("ff-lt"))?.label || "", έναρξη: dmy(a), λήξη: dmy(b), ημέρες: val("ff-days").replace(".", ","), ονοματεπώνυμο: d.employee.name });
    };
    const collect = () => isLeave
      ? { leave_type: val("ff-lt"), start_date: val("ff-s"), end_date: val("ff-e"), days_requested: val("ff-days"), body: val("ff-body"), details: { notes: val("ff-notes") }, template_version_id: tpl.leave_request_body?.id }
      : { body: val("ff-body"), details: { subject: val("ff-subj") } };
    const save = async () => { await api.saveRequest(T, collect()); $("#ff-saved").textContent = "Αποθηκεύτηκε προσωρινά " + new Date().toLocaleTimeString("el-GR", { hour: "2-digit", minute: "2-digit" }); };
    const queue = () => { clearTimeout(saveTimer); saveTimer = setTimeout(() => save().catch((e) => ($("#ff-m").textContent = e.message)), 1500); };
    $$(".k-sign input:not([type=file]), .k-sign select, .k-sign textarea").forEach((x) => (x.oninput = () => { if (x.id === "ff-body") edited = true; regen(); $("#ff-m").textContent = ""; queue(); }));
    regen();
    $("#ff-file").onchange = async (e) => {
      const file = e.target.files[0]; e.target.value = ""; if (!file) return;
      try {
        const ext = (file.name.split(".").pop() || "").toLowerCase(); const mime = MIMES[ext];
        if (!mime) throw new Error("Επιτρέπονται PDF ή εικόνες."); if (file.size > 4194304) throw new Error("Το αρχείο ξεπερνά τα 4 MB.");
        const buf = new Uint8Array(await file.arrayBuffer()); let bin = ""; for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
        await api.attach(T, { name: file.name.slice(0, 200), mime, data: btoa(bin) });
        $("#ff-att").textContent = ($("#ff-att").textContent ? $("#ff-att").textContent + ", " : "Επισυνάφθηκαν: ") + file.name;
      } catch (err) { $("#ff-m").textContent = err.message; }
    };
    $("#ff-done").onclick = async () => {
      const btn = $("#ff-done"); btn.disabled = true; clearTimeout(saveTimer);
      try { await save(); await api.finishRequest(T); msg("Ευχαριστούμε!", "Το αίτημά σας καταγράφηκε. Ο manager θα το ελέγξει και θα το υποβάλει. Η υποβολή δεν αποτελεί έγκριση.", true); }
      catch (e) { $("#ff-m").textContent = e.message; btn.disabled = false; }
    };
  }

  // ─────────── Αξιολόγηση ───────────
  function assessmentIntro(d) {
    if (!d.open) {
      const before = new Date(d.now) < new Date(d.starts_at);
      return msg(before ? "Η αξιολόγηση δεν έχει ξεκινήσει" : "Η προθεσμία έληξε", `${before ? "Διαθέσιμη από" : "Έληξε στις"} ${athens(before ? d.starts_at : d.ends_at)} (ώρα Ελλάδας).${before ? "" : " Οι απαντήσεις δεν υποβλήθηκαν."}`);
    }
    const started = Object.keys(d.answers || {}).length > 0;
    shell(d.employee.name, `<div class="eyebrow">Αξιολόγηση</div><h2 style="font-size:26px">${h(d.title)}</h2>
      ${d.description ? `<p style="margin-top:10px;white-space:pre-wrap">${h(d.description)}</p>` : ""}
      <div class="deadline">Προθεσμία υποβολής: <strong>${athens(d.ends_at)}</strong> (ώρα Ελλάδας)</div>
      <p class="muted" style="margin-top:10px">${d.questions.length} ερωτήσεις. Οι απαντήσεις αποθηκεύονται προσωρινά καθώς προχωράτε· η αξιολόγηση θεωρείται ολοκληρωμένη μόνο με την «Οριστική υποβολή». Στις ερωτήσεις αυτοαξιολόγησης δεν υπάρχει σωστή ή λάθος απάντηση.</p>
      <p style="margin-top:6px"><strong>${h(d.employee.name)}</strong> · ${h(d.employee.code)} · ${h(d.employee.store)}</p>
      <div class="k-actions"><button class="btn primary" id="fa-go">${started ? "Συνέχεια" : "Έναρξη"}</button></div>`);
    $("#fa-go").onclick = () => assessmentForm(d);
  }

  function assessmentForm(d) {
    const ans = { ...(d.answers || {}) };
    let timer, sending = false;
    const sections = [...new Set(d.questions.map((q) => q.section))];
    const qHtml = (q, i) => {
      const v = ans[q.id];
      let input = "";
      if (q.qtype === "single") input = q.options.map((o) => `<label class="opt"><input type="radio" name="q${q.id}" value="${h(o.key)}" ${v === o.key ? "checked" : ""}> <span>${h(o.label)}</span></label>`).join("");
      if (q.qtype === "multi") input = `<p class="muted small">Επιλέξτε όσες ισχύουν.</p>` + q.options.map((o) => `<label class="opt"><input type="checkbox" name="q${q.id}" value="${h(o.key)}" ${(v || []).includes(o.key) ? "checked" : ""}> <span>${h(o.label)}</span></label>`).join("");
      if (q.qtype === "scale") { const n = []; for (let x = q.scale_min; x <= q.scale_max; x++) n.push(x); input = `<div class="scale">${q.scale_min_label ? `<span class="muted small">${h(q.scale_min_label)}</span>` : ""}${n.map((x) => `<label class="sc"><input type="radio" name="q${q.id}" value="${x}" ${v === x ? "checked" : ""}><span>${x}</span></label>`).join("")}${q.scale_max_label ? `<span class="muted small">${h(q.scale_max_label)}</span>` : ""}</div>`; }
      if (q.qtype === "text") input = `<textarea name="q${q.id}" rows="4" maxlength="4000">${h(v || "")}</textarea>`;
      return `<div class="fq" data-q="${q.id}"><div class="fq-t"><span class="muted">${i + 1}.</span> ${h(q.text)}${q.required ? ` <span class="req">*</span>` : ` <span class="muted small">(προαιρετική)</span>`}</div>${input}</div>`;
    };
    let idx = 0;
    shell(d.employee.name, `<div class="eyebrow">${h(d.title)}</div>
      <div class="deadline sticky">Προθεσμία: <strong>${athens(d.ends_at)}</strong> (ώρα Ελλάδας) · <span id="fa-prog"></span> · <span id="fa-saved" class="muted"></span></div>
      ${sections.map((s) => `<h3 class="fsec">${h(s)}</h3>${d.questions.filter((q) => q.section === s).map((q) => qHtml(q, idx++)).join("")}`).join("")}
      <p id="fa-m" class="form-msg"></p>
      <div class="k-actions"><button class="btn primary" id="fa-submit">Οριστική υποβολή</button></div>`);
    const read = () => {
      for (const q of d.questions) {
        const els = $$(`[name="q${q.id}"]`);
        if (q.qtype === "single") { const c = els.find((x) => x.checked); if (c) ans[q.id] = c.value; else delete ans[q.id]; }
        if (q.qtype === "multi") { const c = els.filter((x) => x.checked).map((x) => x.value); if (c.length) ans[q.id] = c; else delete ans[q.id]; }
        if (q.qtype === "scale") { const c = els.find((x) => x.checked); if (c) ans[q.id] = Number(c.value); else delete ans[q.id]; }
        if (q.qtype === "text") { const t = els[0].value.trim(); if (t) ans[q.id] = t; else delete ans[q.id]; }
      }
      const req = d.questions.filter((q) => q.required);
      $("#fa-prog").textContent = `${req.filter((q) => ans[q.id] !== undefined).length}/${req.length} υποχρεωτικές`;
    };
    const save = async () => { try { await api.saveAnswers(T, ans); $("#fa-saved").textContent = "αποθηκεύτηκε " + new Date().toLocaleTimeString("el-GR", { hour: "2-digit", minute: "2-digit" }); } catch (e) { $("#fa-m").textContent = e.message; if (/προθεσμία|έληξε/i.test(e.message)) expired(); } };
    const expired = () => msg("Η προθεσμία έληξε", "Η αξιολόγηση δεν υποβλήθηκε. Οι προσωρινές απαντήσεις δεν θεωρούνται ολοκληρωμένη αξιολόγηση.");
    $$(".fq input, .fq textarea").forEach((x) => (x.oninput = x.onchange = () => { read(); $(".fq.missing", root)?.classList.remove("missing"); clearTimeout(timer); timer = setTimeout(save, 1200); }));
    read();
    $("#fa-submit").onclick = async () => {
      if (sending) return;
      read();
      const miss = d.questions.filter((q) => q.required && ans[q.id] === undefined);
      $$(".fq").forEach((x) => x.classList.toggle("missing", miss.some((q) => q.id === x.dataset.q)));
      if (miss.length) { $("#fa-m").textContent = `Συμπληρώστε ${miss.length} υποχρεωτικές ερωτήσεις (σημειώνονται με κόκκινο).`; $(".fq.missing").scrollIntoView({ behavior: "smooth", block: "center" }); return; }
      if (!confirm("Οριστική υποβολή; Μετά δεν μπορείτε να αλλάξετε τις απαντήσεις.")) return;
      sending = true; const btn = $("#fa-submit"); btn.disabled = true; btn.textContent = "Υποβολή…"; clearTimeout(timer);
      try { await api.submitAssessment(T, ans); msg("Η αξιολόγηση υποβλήθηκε", "Ευχαριστούμε για τον χρόνο σας.", true); }
      catch (e) { sending = false; btn.disabled = false; btn.textContent = "Οριστική υποβολή"; $("#fa-m").textContent = e.message; if (/προθεσμία|έληξε/i.test(e.message)) expired(); }
    };
  }

  // Κλείσιμο καρτέλας/ανανέωση: η φόρμα ξαναφορτώνει από τον server (η συνεδρία μένει μόνο σε αυτή την καρτέλα)
  window.addEventListener("hashchange", () => history.replaceState(null, "", location.pathname + "#/fill"));
  start();
}
