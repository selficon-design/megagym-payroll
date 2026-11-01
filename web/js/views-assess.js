// Αξιολογήσεις: ερωτηματολόγια (ΓΔ), εισαγωγή Excel, διαθεσιμότητα, έναρξη συμπλήρωσης, αποτελέσματα, αναφορές
import { S, can, role, getEmployees, activeSpecialties, visibleStores, invalidate } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, confirmBox, norm, downloadXlsx, loadScript } from "./util.js";
import { athens, athensInput, attemptBadge, ATTEMPT_STATE, demoNotice } from "./hr-common.js";
import { enterFill } from "./fill-launch.js";

const view = () => $("#view");
const LETTERS = ["Α", "Β", "Γ", "Δ", "Ε", "ΣΤ"];
const COLS = ["Ειδικότητα", "Ενότητα", "Ερώτηση", "Τύπος απάντησης", ...LETTERS.map((l) => `Επιλογή ${l}`), "Σωστή απάντηση", "Βαθμοί", "Υποχρεωτική", "Σειρά εμφάνισης"];
const QTYPE_GR = { single: "Μία επιλογή", multi: "Πολλές επιλογές", scale: "Κλίμακα", text: "Ελεύθερο κείμενο" };
const Q_STATUS = { draft: ["Πρόχειρο", "b-missing"], active: ["Ενεργό", "b-signed"], closed: ["Κλειστό", "b-voided"] };
const qBadge = (s) => `<span class="badge ${Q_STATUS[s][1]}">${Q_STATUS[s][0]}</span>`;
const num = (v) => (v === null || v === undefined ? "—" : String(Number(v)).replace(".", ","));
const pctOf = (a) => (a.score !== null && a.score !== undefined && Number(a.max_score) > 0 ? (100 * a.score) / a.max_score : null);
const fmtP = (v) => (v === null ? "—" : v.toLocaleString("el-GR", { maximumFractionDigits: 1 }) + "%");

// ═══════════════════════ Λίστα ερωτηματολογίων ═══════════════════════
export async function assessments() {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αξιολογήσεις"));
  if (!can.assessResults()) return assessRun(new URLSearchParams());
  const [qs, atts] = await Promise.all([S.api.questionnaires(), S.api.attempts()]);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Αξιολογήσεις</div><h1>Ερωτηματολόγια</h1>
    <p class="muted">Ο ίδιος ο εργαζόμενος απαντά, σε απομονωμένη οθόνη. Αυτή η ενότητα είναι διαφορετική από την «αρνητική αξιολόγηση» που συντάσσει ο manager.</p></div>
    <div class="row-actions"><button class="btn" id="as-tpl">⇩ Πρότυπο Excel</button><a class="btn" href="#/assess-reports">Αναφορές</a><a class="btn" href="#/assess-run">Έναρξη συμπλήρωσης</a>${can.assessAdmin() ? `<button class="btn primary" id="as-new">+ Νέο ερωτηματολόγιο</button>` : ""}</div></div>
  <div class="card">${qs.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Τίτλος</th><th>Ειδικότητες</th><th>Διαθεσιμότητα (ώρα Ελλάδας)</th><th class="r">Υποβολές</th><th>Κατάσταση</th></tr></thead><tbody>
    ${qs.map((q) => { const a = atts.filter((x) => x.questionnaire_id === q.id); return `<tr class="click" data-q="${h(q.id)}"><td><strong>${h(q.title)}</strong>${q.description ? `<span class="sub">${h(q.description.slice(0, 90))}</span>` : ""}</td>
      <td class="small">${h(q.specialties.join(", ") || "—")}</td><td class="small">${q.starts_at ? `${athens(q.starts_at)} → ${athens(q.ends_at)}` : "—"}</td>
      <td class="r num">${a.filter((x) => x.status !== "in_progress").length}${a.some((x) => x.status === "pending_manual") ? ` <span class="badge b-pending">βαθμολόγηση</span>` : ""}</td><td>${qBadge(q.status)}</td></tr>`; }).join("")}
    </tbody></table></div>` : `<div class="empty"><div class="big">☑︎</div>Δεν υπάρχουν ερωτηματολόγια ακόμη.</div>`}</div>`;
  $$("tr.click").forEach((tr) => (tr.onclick = () => (location.hash = `#/assessment?id=${tr.dataset.q}`)));
  $("#as-tpl").onclick = downloadTemplate;
  $("#as-new") && ($("#as-new").onclick = () => openDialog(`<div class="dlg-head"><h2>Νέο ερωτηματολόγιο</h2><button class="icon-btn" data-close>✕</button></div>
    <label>Τίτλος</label><input id="nq-t" maxlength="200"><label>Περιγραφή</label><textarea id="nq-d" rows="3" maxlength="2000"></textarea><p id="nq-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="nq-ok">Δημιουργία (πρόχειρο)</button></div>`, {
    onOpen() { $("#nq-ok").onclick = async () => { try { const r = await S.api.qCreate($("#nq-t").value, $("#nq-d").value); closeDialog(); location.hash = `#/assessment?id=${r.id}&tab=questions`; } catch (e) { $("#nq-m").textContent = e.message; } }; },
  }));
}

function downloadTemplate() {
  const specs = activeSpecialties();
  downloadXlsx("Πρότυπο_Ερωτηματολογίου.xlsx", {
    "Ερωτήσεις": [COLS,
      [specs[0] || "Ρεσεψιόν", "Πωλήσεις", "Τι σημαίνει DR;", "Μία επιλογή", "Άμεση εγγραφή", "Δοκιμαστικό", "Χαμένη ενημέρωση", "", "", "", "Α", "1", "Ναι", "1"],
      [specs[0] || "Ρεσεψιόν", "Πωλήσεις", "Ποια προγράμματα είναι Exclusive;", "Πολλές επιλογές", "MEGA BODY", "MEGA MUSCLE", "Fitness", "Pilates", "", "", "Α,Β", "2", "Ναι", "2"],
      [specs[0] || "Ρεσεψιόν", "Αυτοαξιολόγηση", "Πόσο άνετα χειρίζεστε τις τηλεφωνικές ενημερώσεις;", "Κλίμακα", "1", "5", "Καθόλου", "Πολύ", "", "", "", "", "Ναι", "3"],
      ["", "Γενικά", "Περιγράψτε μια δύσκολη συνομιλία με μέλος και πώς τη χειριστήκατε.", "Ελεύθερο κείμενο", "", "", "", "", "", "", "", "", "Όχι", "4"]],
    "Οδηγίες": [["Στήλη", "Τι γράφω"],
      ["Γενικά", "Κάθε γραμμή = μία ερώτηση. Μην αλλάζετε τα ονόματα των στηλών. Μην χρησιμοποιείτε τύπους (=…) ή μακροεντολές: δεν εκτελούνται και η γραμμή απορρίπτεται."],
      ["Ειδικότητα", `Μία από: ${specs.join(", ")}. Κενό = η ερώτηση εμφανίζεται σε όλες τις ειδικότητες του ερωτηματολογίου.`],
      ["Ενότητα", "Ομάδα ερωτήσεων (π.χ. Πωλήσεις). Κενό = «Γενικά». Η βαθμολογία δείχνεται και ανά ενότητα."],
      ["Τύπος απάντησης", "Μία επιλογή · Πολλές επιλογές · Κλίμακα · Ελεύθερο κείμενο"],
      ["Επιλογή Α – ΣΤ", "Για «Μία/Πολλές επιλογές»: τα κείμενα των επιλογών, συνεχόμενα από την Α (τουλάχιστον Α και Β)."],
      ["Κλίμακα", "Επιλογή Α = ελάχιστη τιμή (π.χ. 1), Επιλογή Β = μέγιστη (π.χ. 5, έως 10 βήματα). Προαιρετικά: Επιλογή Γ = ετικέτα ελάχιστης, Επιλογή Δ = ετικέτα μέγιστης."],
      ["Σωστή απάντηση", "Μία επιλογή: ένα γράμμα (π.χ. Α). Πολλές επιλογές: γράμματα με κόμμα (π.χ. Α,Γ). Κλίμακα: κενό (αυτοαξιολόγηση, χωρίς σωστό/λάθος) ή ΑΝΑΛΟΓΙΚΑ (βαθμός ανάλογος της τιμής). Ελεύθερο κείμενο: κενό."],
      ["Βαθμοί", "Μόνο όπου υπάρχει κανόνας βαθμολόγησης. Ελεύθερο κείμενο με βαθμούς → χειροκίνητη βαθμολόγηση από ΓΔ/HR. Κλίμακα με βαθμούς → χρειάζεται ΑΝΑΛΟΓΙΚΑ."],
      ["Πολλές σωστές", "Ο κανόνας (όλα-ή-τίποτα ή μερική βαθμολογία) ορίζεται στην εφαρμογή πριν από την ενεργοποίηση."],
      ["Υποχρεωτική", "Ναι ή Όχι"],
      ["Σειρά εμφάνισης", "Ακέραιος. Κενό = σειρά γραμμής."],
      ["Μετά το ανέβασμα", "Εμφανίζεται προεπισκόπηση και έλεγχος με αριθμό γραμμής. Αποθηκεύεται ως πρόχειρο· ΔΕΝ ενεργοποιείται αυτόματα."]],
  });
}

/** Ανάγνωση Excel χωρίς εκτέλεση τύπων/μακροεντολών. Γραμμές με τύπους σημειώνονται ως λάθος. */
async function readQuestions(file) {
  await loadScript("vendor/xlsx.js"); const X = window.XLSX;
  const wb = X.read(await file.arrayBuffer(), { type: "array", cellFormula: true, bookVBA: false, cellHTML: false, cellText: true, sheetStubs: true });
  const ws = wb.Sheets["Ερωτήσεις"] || wb.Sheets[wb.SheetNames[0]];
  if (!ws) throw new Error("Δεν βρέθηκε φύλλο «Ερωτήσεις».");
  const range = X.utils.decode_range(ws["!ref"] || "A1:A1");
  const cell = (r, c) => ws[X.utils.encode_cell({ r, c })];
  const head = Array.from({ length: COLS.length }, (_, c) => String(cell(range.s.r, c)?.w ?? cell(range.s.r, c)?.v ?? "").trim());
  const missing = COLS.filter((c, i) => norm(head[i]) !== norm(c));
  if (missing.length) throw new Error(`Οι στήλες δεν ταιριάζουν με το πρότυπο (γραμμή 1). Λείπει ή είναι σε λάθος θέση: ${missing.join(", ")}.`);
  const rows = [], formulaRows = [];
  for (let r = range.s.r + 1; r <= range.e.r; r++) {
    const vals = Array.from({ length: COLS.length }, (_, c) => { const x = cell(r, c); if (x?.f) formulaRows.push(r + 1); return String(x?.w ?? x?.v ?? "").trim(); });
    if (!vals.some(Boolean)) continue;
    rows.push({ row: r + 1, specialty: vals[0], section: vals[1], text: vals[2], type: vals[3], options: vals.slice(4, 10), correct: vals[10], points: vals[11], required: vals[12], order: vals[13] });
  }
  return { rows, formulaRows: [...new Set(formulaRows)] };
}

// ═══════════════════════ Ερωτηματολόγιο (ΓΔ / HR) ═══════════════════════
export async function assessmentView(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αξιολογήσεις"));
  if (!can.assessResults()) return (view().innerHTML = `<div class="card empty">Μόνο για Γενική Διευθύντρια και HR.</div>`);
  const id = params.get("id"), tab = params.get("tab") || "settings";
  const q = await S.api.questionnaire(id);
  const latest = q.versions[0], current = q.versions.find((v) => v.id === q.current_version_id);
  const admin = can.assessAdmin();
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Ερωτηματολόγιο ${current ? `· ενεργή έκδοση ${current.version}` : ""}${latest?.status === "draft" && current ? ` · πρόχειρη έκδοση ${latest.version}` : ""}</div><h1>${h(q.title)}</h1>
    <p class="muted">${qBadge(q.status)} ${q.starts_at ? `Διαθέσιμο ${athens(q.starts_at)} → ${athens(q.ends_at)} (ώρα Ελλάδας)` : "Χωρίς διάστημα διαθεσιμότητας"}</p></div>
    <a class="btn" href="#/assessments">← Ερωτηματολόγια</a></div>
  <div class="tabs">${[["settings", "Ρυθμίσεις & διαθεσιμότητα"], ["questions", "Ερωτήσεις"], ["results", "Αποτελέσματα"]].map(([k, l]) => `<a href="#/assessment?id=${id}&tab=${k}" class="${k === tab ? "on" : ""}">${l}</a>`).join("")}</div>
  <div id="qa-body"></div>`;
  const body = $("#qa-body");
  const reload = () => { invalidate(); assessmentView(params); };
  if (tab === "settings") return settingsTab(q, body, admin, reload);
  if (tab === "questions") return questionsTab(q, body, admin, reload);
  return resultsTab(q, body);
}

async function settingsTab(q, body, admin, reload) {
  const emps = await getEmployees();
  const latest = q.versions[0];
  const checks = admin ? await S.api.qCheck(q.id) : [];
  const dis = admin ? "" : "disabled";
  body.innerHTML = `<div class="grid g2">
    <div class="card"><h3>Στοιχεία</h3>
      <label>Τίτλος</label><input id="qs-t" maxlength="200" value="${h(q.title)}" ${dis}>
      <label>Περιγραφή (τη βλέπει ο εργαζόμενος πριν ξεκινήσει)</label><textarea id="qs-d" rows="3" maxlength="2000" ${dis}>${h(q.description || "")}</textarea>
      <label>Ειδικότητες</label><div class="chips" id="qs-specs">${activeSpecialties().map((s) => `<label class="chip ${q.specialties.includes(s) ? "on" : ""}" style="margin:0"><input type="checkbox" value="${h(s)}" ${q.specialties.includes(s) ? "checked" : ""} hidden ${dis}>${h(s)}</label>`).join("")}</div>
      <label>Συμμετέχοντες</label>
      <div class="chips"><label class="chip ${!q.participants ? "on" : ""}" style="margin:0"><input type="radio" name="qs-p" value="all" ${!q.participants ? "checked" : ""} hidden ${dis}>Όλοι οι ενεργοί των ειδικοτήτων</label>
        <label class="chip ${q.participants ? "on" : ""}" style="margin:0"><input type="radio" name="qs-p" value="some" ${q.participants ? "checked" : ""} hidden ${dis}>Συγκεκριμένοι</label></div>
      <div id="qs-plist" class="plist" ${q.participants ? "" : "hidden"}></div>
      ${admin ? `<p id="qs-m" class="form-msg"></p><button class="btn primary" id="qs-save" style="margin-top:6px">Αποθήκευση στοιχείων</button>` : ""}
    </div>
    <div>
      <div class="card"><h3>Διαθεσιμότητα</h3><p class="muted small" style="margin-top:6px">Ένα συνεχόμενο διάστημα. Οι ώρες είναι ώρα Ελλάδας (με θερινή/χειμερινή ώρα). Έναρξη και υποβολή ελέγχονται στον server.</p>
        <div class="grid g2"><div><label>Έναρξη</label><input type="datetime-local" id="qs-s" value="${athensInput(q.starts_at)}" ${dis}></div><div><label>Λήξη</label><input type="datetime-local" id="qs-e" value="${athensInput(q.ends_at)}" ${dis}></div></div>
        ${admin ? `<label>Σημείωση αλλαγής (π.χ. «παράταση λόγω αργίας»)</label><input id="qs-n" maxlength="300"><p id="qs-wm" class="form-msg"></p><button class="btn" id="qs-win">Αποθήκευση διαστήματος</button>` : ""}
        ${q.log.length ? `<h4 style="margin-top:16px">Ιστορικό αλλαγών</h4>${q.log.map((l) => `<div class="list-item small"><div class="grow">${l.old_starts ? `${athens(l.old_starts)} → ${athens(l.old_ends)}<br>` : ""}<strong>${athens(l.new_starts)} → ${athens(l.new_ends)}</strong>${l.note ? ` · ${h(l.note)}` : ""}<div class="muted">${h(l.actor)} · ${athens(l.at)}</div></div></div>`).join("")}` : ""}
      </div>
      <div class="card" style="margin-top:16px"><h3>Ενεργοποίηση</h3>
        <label>Κανόνας βαθμολόγησης για «Πολλές επιλογές»</label>
        <select id="qs-rule" ${dis}><option value="">— δεν έχει οριστεί —</option><option value="all_or_nothing" ${latest?.multi_rule === "all_or_nothing" ? "selected" : ""}>Όλα ή τίποτα: πλήρεις βαθμοί μόνο αν επιλεγούν ακριβώς οι σωστές</option><option value="partial" ${latest?.multi_rule === "partial" ? "selected" : ""}>Μερική: βαθμοί × (σωστές επιλογές − λάθος επιλογές) ÷ πλήθος σωστών, ελάχιστο 0</option></select>
        ${checks.length ? `<div class="note warn" style="margin-top:12px"><strong>Πριν από την ενεργοποίηση:</strong><ul style="margin:6px 0 0 18px">${checks.map((c) => `<li>${h(c)}</li>`).join("")}</ul></div>` : admin ? `<div class="note" style="margin-top:12px">Οι έλεγχοι πέρασαν.</div>` : ""}
        ${admin ? `<div class="row-actions" style="margin-top:14px">${latest?.status === "draft" || q.status !== "active" ? `<button class="btn primary" id="qs-pub" ${checks.length ? "disabled" : ""}>${q.status === "active" ? `Ενεργοποίηση έκδοσης ${latest.version}` : "Ενεργοποίηση"}</button>` : ""}${q.status === "active" ? `<button class="btn danger" id="qs-close">Κλείσιμο</button>` : ""}</div>` : ""}
        <p class="muted small" style="margin-top:10px">Δεν έχουν οριστεί χρονόμετρο διάρκειας ούτε επαναλήψεις: κάθε εργαζόμενος υποβάλλει μία φορά ανά ερωτηματολόγιο.</p>
      </div>
    </div></div>`;
  const drawP = () => {
    const specs = $$("#qs-specs input:checked").map((i) => i.value);
    const sel = new Set(q.participants || []);
    $("#qs-plist").innerHTML = emps.filter((e) => e.status === "Ενεργός" && specs.includes(e.specialty)).map((e) => `<label class="check"><input type="checkbox" value="${h(e.code)}" ${sel.has(e.code) ? "checked" : ""} ${dis}> ${h(e.last)} ${h(e.first)} <span class="muted small">${h(e.store)} · ${h(e.specialty)}</span></label>`).join("") || `<p class="muted small">Επιλέξτε πρώτα ειδικότητες.</p>`;
  };
  drawP();
  $$("#qs-specs input").forEach((i) => (i.onchange = () => { i.parentElement.classList.toggle("on", i.checked); drawP(); }));
  $$("input[name=qs-p]").forEach((i) => (i.onchange = () => { $$("input[name=qs-p]").forEach((x) => x.parentElement.classList.toggle("on", x.checked)); $("#qs-plist").hidden = i.value === "all"; }));
  if (!admin) return;
  $("#qs-save").onclick = async () => {
    const some = $("input[name=qs-p]:checked").value === "some";
    try { await S.api.qUpdateMeta(q.id, { title: $("#qs-t").value, description: $("#qs-d").value, specialties: $$("#qs-specs input:checked").map((i) => i.value), participants: some ? $$("#qs-plist input:checked").map((i) => i.value) : null }); toast("Αποθηκεύτηκε."); reload(); }
    catch (e) { $("#qs-m").textContent = e.message; }
  };
  $("#qs-win").onclick = async () => {
    try { await S.api.qSetWindow(q.id, $("#qs-s").value, $("#qs-e").value, $("#qs-n").value); toast("Το διάστημα αποθηκεύτηκε και καταγράφηκε."); reload(); }
    catch (e) { $("#qs-wm").textContent = e.message; }
  };
  $("#qs-rule").onchange = async (e) => { try { await S.api.qSetMultiRule(q.id, e.target.value || null); toast("Ο κανόνας αποθηκεύτηκε."); reload(); } catch (err) { toast(err.message, true); } };
  $("#qs-pub") && ($("#qs-pub").onclick = async () => {
    if (!(await confirmBox("Ενεργοποίηση", "Από την έναρξη του διαστήματος το ερωτηματολόγιο θα είναι διαθέσιμο στους εξουσιοδοτημένους χρήστες για συμπλήρωση από τους εργαζόμενους.", { ok: "Ενεργοποίηση" }))) return;
    try { const r = await S.api.qPublish(q.id); if (r.ok) { toast("Ενεργοποιήθηκε."); reload(); } else toast(r.errors.join(" · "), true); } catch (e) { toast(e.message, true); }
  });
  $("#qs-close") && ($("#qs-close").onclick = async () => {
    if (!(await confirmBox("Κλείσιμο ερωτηματολογίου", "Δεν θα μπορεί να ξεκινήσει ή να υποβληθεί νέα συμπλήρωση. Οι υποβολές μένουν.", { ok: "Κλείσιμο", danger: true }))) return;
    try { await S.api.qClose(q.id); reload(); } catch (e) { toast(e.message, true); }
  });
}

const questionRow = (x) => `<tr><td class="num small">${x.row_no}</td><td class="small">${h(x.specialty || "Όλες")}<span class="sub">${h(x.section)}</span></td>
  <td>${h(x.text)}${x.qtype === "scale" ? `<span class="sub">Κλίμακα ${x.scale_min}–${x.scale_max}${x.scale_min_label ? ` (${h(x.scale_min_label)} → ${h(x.scale_max_label || "")})` : ""}</span>` : x.options?.length ? `<span class="sub">${x.options.map((o) => `${o.key}. ${h(o.label)}`).join(" · ")}</span>` : ""}</td>
  <td class="small">${QTYPE_GR[x.qtype]}</td><td class="small">${x.correct?.length ? h(x.correct.join(",")) : x.scale_rule === "linear" ? "ΑΝΑΛΟΓΙΚΑ" : "—"}</td><td class="r num">${num(x.points)}</td><td class="small">${x.required ? "Ναι" : "Όχι"}</td></tr>`;

async function questionsTab(q, body, admin, reload) {
  const latest = q.versions[0];
  const qs = latest ? await S.api.questions(latest.id) : [];
  body.innerHTML = `<div class="card">
    <div class="card-head"><h3>Έκδοση ${latest?.version ?? "—"} · ${latest?.status === "draft" ? "πρόχειρη" : latest?.status === "published" ? "ενεργή" : "αποσυρμένη"}${latest?.source_filename ? ` <span class="muted small">από ${h(latest.source_filename)}</span>` : ""}</h3>
      ${admin ? `<div class="row-actions"><button class="btn" id="qq-tpl">⇩ Πρότυπο</button><label class="btn primary" style="margin:0">⇧ Ανέβασμα Excel<input type="file" id="qq-file" accept=".xlsx,.xls" hidden></label></div>` : ""}</div>
    ${q.status === "active" && admin ? `<div class="note" style="margin-bottom:12px">Οποιαδήποτε αλλαγή ερωτήσεων, σωστών απαντήσεων ή βαθμών δημιουργεί <strong>νέα έκδοση</strong>· οι προηγούμενες υποβολές δεν αλλάζουν.</div>` : ""}
    ${qs.length ? `<div class="table-wrap"><table><thead><tr><th>Γρ.</th><th>Ειδικότητα / Ενότητα</th><th>Ερώτηση</th><th>Τύπος</th><th>Σωστή</th><th class="r">Βαθμοί</th><th>Υποχρ.</th></tr></thead><tbody>${qs.map(questionRow).join("")}</tbody></table></div>`
      : `<div class="empty">Δεν υπάρχουν ερωτήσεις. ${admin ? "Κατεβάστε το πρότυπο, συμπληρώστε το και ανεβάστε το." : ""}</div>`}
    ${q.versions.length > 1 ? `<p class="muted small" style="margin-top:12px">Εκδόσεις: ${q.versions.map((v) => `${v.version} (${{ draft: "πρόχειρη", published: "ενεργή", retired: "αποσυρμένη" }[v.status]})`).join(" · ")}</p>` : ""}
  </div>`;
  if (!admin) return;
  $("#qq-tpl").onclick = downloadTemplate;
  $("#qq-file").onchange = async (e) => {
    const f = e.target.files[0]; e.target.value = ""; if (!f) return;
    try { const { rows, formulaRows } = await readQuestions(f); importPreview(q, rows, formulaRows, f.name, reload); } catch (err) { toast(err.message, true); }
  };
}

/** Προεπισκόπηση: έλεγχος από τον ΙΔΙΟ κανόνα του server, διορθώσεις στη θέση τους, αποθήκευση ως πρόχειρο. */
function importPreview(q, rows, formulaRows, filename, reload) {
  const st = { rows, errors: [] };
  const cols = [["specialty", "Ειδικότητα"], ["section", "Ενότητα"], ["text", "Ερώτηση"], ["type", "Τύπος"], ...LETTERS.map((l, i) => [`o${i}`, l]), ["correct", "Σωστή"], ["points", "Βαθμοί"], ["required", "Υποχρ."], ["order", "Σειρά"]];
  const get = (r, k) => (k[0] === "o" && k.length === 2 ? r.options[Number(k[1])] : r[k]);
  const set = (r, k, v) => { if (k[0] === "o" && k.length === 2) r.options[Number(k[1])] = v; else r[k] = v; };
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(filename)}</div><h2>Προεπισκόπηση ερωτήσεων</h2></div><button class="icon-btn" data-close>✕</button></div>
    <div id="ip-sum"></div><div class="table-wrap" style="max-height:55vh;margin-top:12px"><table class="edit"><thead><tr><th>Γρ.</th>${cols.map(([, l]) => `<th>${l}</th>`).join("")}<th></th></tr></thead><tbody id="ip-rows"></tbody></table></div>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn" id="ip-check">Νέος έλεγχος</button><button class="btn primary" id="ip-save" disabled>Αποθήκευση ως πρόχειρο</button></div>`, {
    wide: true,
    async onOpen() {
      const draw = () => {
        const err = Object.fromEntries(st.errors.map((e) => [e.row, e.msg]));
        $("#ip-rows").innerHTML = st.rows.map((r, i) => `<tr class="${err[r.row] ? "bad" : ""}"><td class="num">${r.row}</td>${cols.map(([k]) => `<td><input data-i="${i}" data-k="${k}" value="${h(get(r, k) ?? "")}" class="${k === "text" ? "wide" : ""}"></td>`).join("")}
          <td class="small">${err[r.row] ? `<span class="err-txt">${h(err[r.row])}</span>` : `<span class="badge b-signed">OK</span>`}</td></tr>`).join("");
        $("#ip-sum").innerHTML = st.errors.length ? `<div class="note bad">Βρέθηκαν ${st.errors.length} λάθη. Διορθώστε τα εδώ ή στο αρχείο και πατήστε «Νέος έλεγχος».<ul style="margin:6px 0 0 18px">${st.errors.slice(0, 12).map((e) => `<li>${e.row ? `Γραμμή ${e.row}: ` : ""}${h(e.msg)}</li>`).join("")}</ul></div>`
          : `<div class="note">Όλες οι ${st.rows.length} ερωτήσεις είναι έγκυρες. Θα αποθηκευτούν ως <strong>πρόχειρο</strong>· η ενεργοποίηση γίνεται χωριστά.</div>`;
        $$("#ip-rows input").forEach((inp) => (inp.oninput = () => { set(st.rows[inp.dataset.i], inp.dataset.k, inp.value); $("#ip-save").disabled = true; }));
        $("#ip-save").disabled = st.errors.length > 0;
      };
      const check = async () => {
        const res = await S.api.qParse(st.rows);
        st.errors = [...res.errors, ...formulaRows.filter((r) => st.rows.some((x) => x.row === r)).map((r) => ({ row: r, msg: "Η γραμμή περιέχει τύπο Excel (=…). Οι τύποι δεν εκτελούνται· γράψτε απλή τιμή." }))];
        draw();
      };
      $("#ip-check").onclick = () => { formulaRows = []; check().catch((e) => toast(e.message, true)); };
      $("#ip-save").onclick = async () => {
        try { const r = await S.api.qSaveQuestions(q.id, st.rows, filename); if (!r.ok) { st.errors = r.errors; draw(); return; } closeDialog(); toast(`Αποθηκεύτηκαν ${r.count} ερωτήσεις ως πρόχειρο.`); reload(); }
        catch (e) { toast(e.message, true); }
      };
      await check();
    },
  });
}

async function resultsTab(q, body) {
  const [targets, atts, vers] = await Promise.all([q.status === "draft" ? [] : S.api.assessmentTargets(q.id), S.api.attempts({ questionnaire: q.id }), S.api.versionsAll()]);
  const vN = Object.fromEntries(vers.map((v) => [v.id, v.version]));
  const byEmp = Object.fromEntries(atts.map((a) => [a.employee_code, a]));
  const counts = {}; for (const t of targets) counts[t.state] = (counts[t.state] || 0) + 1;
  body.innerHTML = `<div class="card">
    <div class="chips" style="margin-bottom:12px">${Object.entries(ATTEMPT_STATE).map(([k, v]) => `<span class="chip">${v.label}<span class="n">${counts[k] || 0}</span></span>`).join("")}</div>
    ${targets.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα · Ειδικότητα</th><th>Έκδοση</th><th>Άνοιξε</th><th>Έναρξη / Υποβολή</th><th>Κατάσταση</th><th class="r">Αποτέλεσμα</th></tr></thead><tbody>
      ${targets.map((t) => { const a = byEmp[t.employee_code]; return `<tr ${a ? `class="click" data-att="${h(a.id)}"` : ""}><td><a href="#/employee?code=${encodeURIComponent(t.employee_code)}&tab=assess" onclick="event.stopPropagation()">${h(t.employee_name)}</a><span class="sub">${h(t.employee_code)}</span></td>
        <td class="small">${h(a?.store || t.store)} · ${h(a?.specialty || t.specialty)}</td><td class="num">${a ? vN[a.version_id] : "—"}</td><td class="small">${h(a?.opened_by || "—")}</td>
        <td class="small">${a ? athens(a.started_at) : "—"}${a?.submitted_at ? `<br>${athens(a.submitted_at)}` : ""}</td><td>${attemptBadge(t.state)}</td>
        <td class="r num">${a && a.max_score ? `${num(a.score)} / ${num(a.max_score)}<span class="sub">${fmtP(pctOf(a))}</span>` : "—"}</td></tr>`; }).join("")}
      </tbody></table></div>` : `<div class="empty">${q.status === "draft" ? "Το ερωτηματολόγιο δεν έχει ενεργοποιηθεί." : "Δεν υπάρχουν εργαζόμενοι για τις επιλεγμένες ειδικότητες."}</div>`}</div>`;
  $$("[data-att]", body).forEach((tr) => (tr.onclick = () => attemptDialog(tr.dataset.att)));
}

/** Αναλυτικές απαντήσεις, βαθμοί ανά ερώτηση/ενότητα και χειροκίνητη βαθμολόγηση (ΓΔ, HR). */
export async function attemptDialog(attemptId) {
  const atts = await S.api.attempts();
  const a = atts.find((x) => x.id === attemptId);
  if (!a) return toast("Δεν βρέθηκε.", true);
  const [qs, ans, q] = await Promise.all([S.api.questions(a.version_id), S.api.attemptAnswers(a.id), S.api.questionnaire(a.questionnaire_id)]);
  const ver = q.versions.find((v) => v.id === a.version_id);
  const A = Object.fromEntries(ans.map((x) => [x.question_id, x]));
  const shown = qs.filter((x) => !x.specialty || x.specialty === a.specialty);
  const sections = {};
  for (const x of shown) { const s = (sections[x.section] ??= { got: 0, max: 0, pending: false }); const y = A[x.id]; if (y?.max_points) { s.max += Number(y.max_points); if (y.needs_manual && !y.graded_at) s.pending = true; else s.got += Number(y.points || 0); } }
  const fmtAns = (x, v) => {
    if (v === undefined || v === null) return `<span class="muted">— χωρίς απάντηση</span>`;
    if (x.qtype === "single") return h(`${v}. ${x.options.find((o) => o.key === v)?.label || ""}`);
    if (x.qtype === "multi") return (v || []).map((k) => h(`${k}. ${x.options.find((o) => o.key === k)?.label || ""}`)).join("<br>");
    if (x.qtype === "scale") return `${h(v)} <span class="muted">(${x.scale_min}–${x.scale_max})</span>`;
    return `<span style="white-space:pre-wrap">${h(v)}</span>`;
  };
  const inProgress = a.status === "in_progress";
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(q.title)} · έκδοση ${ver?.version}</div><h2>${h(a.employee_name)}</h2>
      <p class="muted small">${h(a.store)} · ${h(a.specialty)} (κατά τη συμπλήρωση) · άνοιξε ${h(a.opened_by)} · έναρξη ${athens(a.started_at)}${a.submitted_at ? ` · υποβολή ${athens(a.submitted_at)}` : ""}</p></div><button class="icon-btn" data-close>✕</button></div>
    ${inProgress ? `<div class="note warn">Δεν έχει υποβληθεί οριστικά. Οι προσωρινές απαντήσεις δεν θεωρούνται ολοκληρωμένη αξιολόγηση και δεν βαθμολογούνται.</div>` : `
    <div class="grid g3" style="margin-top:12px"><div class="card kpi"><div class="label">Συνολικό</div><div class="value num">${a.max_score ? `${num(a.score)} / ${num(a.max_score)}` : "—"}</div><div class="hint">${a.max_score ? fmtP(pctOf(a)) : "χωρίς έγκυρο κανόνα βαθμολόγησης"}${a.status === "pending_manual" ? " · αναμένει χειροκίνητη βαθμολόγηση" : ""}</div></div>
      <div class="card" style="grid-column:span 2"><div class="label muted small">Ανά ενότητα</div>${Object.entries(sections).map(([s, v]) => `<div class="small">${h(s)}: <strong>${v.max ? (v.pending ? "αναμένει βαθμολόγηση" : `${num(v.got)} / ${num(v.max)}`) : "χωρίς βαθμολογία (π.χ. αυτοαξιολόγηση)"}</strong></div>`).join("")}</div></div>`}
    <div class="table-wrap" style="margin-top:14px;max-height:55vh"><table><thead><tr><th>Ερώτηση</th><th>Απάντηση</th><th>Σωστή</th><th class="r">Βαθμοί</th></tr></thead><tbody>
    ${shown.map((x) => { const y = A[x.id]; const v = inProgress ? undefined : y?.answer; return `<tr><td class="small"><span class="muted">${h(x.section)}</span><br>${h(x.text)}</td><td class="small">${inProgress ? `<span class="muted">—</span>` : fmtAns(x, v)}</td>
      <td class="small">${x.correct?.length ? h(x.correct.join(",")) + (y?.is_correct === true ? " ✓" : y?.is_correct === false ? " ✗" : "") : x.qtype === "scale" && !x.points ? "αυτοαξιολόγηση" : "—"}</td>
      <td class="r num">${!y?.max_points ? "—" : y.needs_manual && !y.graded_at ? `<input class="grade" data-q="${x.id}" inputmode="decimal" placeholder="0–${num(y.max_points)}" style="width:80px">` : `${num(y.points)} / ${num(y.max_points)}${y.graded_by ? `<span class="sub">${h(y.graded_by)}</span>` : ""}`}</td></tr>`; }).join("")}
    </tbody></table></div>
    <p id="ad-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Κλείσιμο</button>${ans.some((y) => y.needs_manual && !y.graded_at) ? `<button class="btn primary" id="ad-grade">Αποθήκευση βαθμών</button>` : ""}</div>`, {
    wide: true,
    onOpen() {
      $("#ad-grade") && ($("#ad-grade").onclick = async () => {
        try {
          for (const inp of $$("input.grade")) { if (inp.value.trim() === "") continue; await S.api.assessmentGrade(a.id, inp.dataset.q, Number(inp.value.replace(",", "."))); }
          closeDialog(); toast("Οι βαθμοί αποθηκεύτηκαν."); window.dispatchEvent(new Event("mg:rerender"));
        } catch (e) { $("#ad-m").textContent = e.message; }
      });
    },
  });
}

// ═══════════════════════ Έναρξη συμπλήρωσης (manager, εκπαιδευτής, HR, ΓΔ) ═══════════════════════
export async function assessRun(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αξιολογήσεις"));
  if (!can.assessOpen()) return (view().innerHTML = `<div class="card empty">Δεν έχετε πρόσβαση.</div>`);
  const open = await S.api.assessmentsOpen();
  const F = (S.filters.run ??= { q: "", search: "" });
  if (!open.some((x) => x.id === F.q)) F.q = open[0]?.id || "";
  const sel = open.find((x) => x.id === F.q);
  const targets = sel ? await S.api.assessmentTargets(sel.id) : [];
  const now = Date.now();
  const inWindow = sel && new Date(sel.starts_at).getTime() <= now && now <= new Date(sel.ends_at).getTime();
  const list = targets.filter((t) => !F.search || norm(`${t.employee_name} ${t.employee_code}`).includes(norm(F.search)));
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Αξιολογήσεις</div><h1>Έναρξη συμπλήρωσης</h1>
    <p class="muted">Επιλέξτε ερωτηματολόγιο και εργαζόμενο. Η συσκευή θα δείχνει ΜΟΝΟ τη φόρμα του εργαζομένου· θα αποσυνδεθείτε και για επιστροφή θα χρειαστεί ο κωδικός σας.${role() === "trainer" ? " Βλέπετε μόνο εργαζόμενους του πεδίου ευθύνης σας." : role() === "manager" ? ` Κατάστημα ${h(S.me.store)}.` : ""}</p></div>
    ${can.assessResults() ? `<a class="btn" href="#/assessments">Ερωτηματολόγια</a>` : ""}</div>
  ${open.length ? `<div class="card">
    <div class="toolbar"><select id="ar-q">${open.map((x) => `<option value="${x.id}" ${x.id === F.q ? "selected" : ""}>${h(x.title)} · έκδοση ${x.version}</option>`).join("")}</select>
      <input type="search" id="ar-s" placeholder="Αναζήτηση εργαζομένου" value="${h(F.search)}"></div>
    <div class="note ${inWindow ? "" : "warn"}">Διαθέσιμο από <strong>${athens(sel.starts_at)}</strong> έως <strong>${athens(sel.ends_at)}</strong> (ώρα Ελλάδας).${inWindow ? "" : " Εκτός διαστήματος: δεν μπορεί να ξεκινήσει συμπλήρωση."}${sel.description ? `<br>${h(sel.description)}` : ""}</div>
    ${list.length ? `<div class="table-wrap" style="margin-top:12px"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα</th><th>Ειδικότητα</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${list.map((t) => `<tr><td><strong>${h(t.employee_name)}</strong><span class="sub">${h(t.employee_code)}</span></td><td data-l="Κατάστημα">${h(t.store)}</td><td data-l="Ειδικότητα">${h(t.specialty)}</td><td>${attemptBadge(t.state)}</td>
        <td class="acts" style="text-align:right">${inWindow && ["not_started", "in_progress"].includes(t.state) ? `<button class="btn sm primary" data-go="${h(t.employee_code)}">${t.state === "in_progress" ? "Συνέχεια" : "Έναρξη"}</button>` : ""}</td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty">Δεν υπάρχουν εργαζόμενοι στο πεδίο σας για αυτό το ερωτηματολόγιο.</div>`}
  </div>` : `<div class="card empty"><div class="big">☑︎</div>Δεν υπάρχει ενεργό ερωτηματολόγιο.</div>`}`;
  $("#ar-q") && ($("#ar-q").onchange = (e) => { F.q = e.target.value; assessRun(params); });
  $("#ar-s") && ($("#ar-s").oninput = (e) => { F.search = e.target.value; assessRun(params).then(() => { const i = $("#ar-s"); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }); });
  $$("[data-go]").forEach((b) => (b.onclick = () => {
    const t = targets.find((x) => x.employee_code === b.dataset.go);
    enterFill({ kind: "assessment", label: `${sel.title} — ${t.employee_name}`, start: () => S.api.fillStartAssessment(sel.id, t.employee_code), returnTo: "#/assess-run" }).catch((e) => toast(e.message, true));
  }));
}

// ═══════════════════════ Αναφορές αξιολογήσεων (ΓΔ, HR) ═══════════════════════
export async function assessReports() {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αξιολογήσεις"));
  if (!can.assessResults()) return (view().innerHTML = `<div class="card empty">Μόνο για Γενική Διευθύντρια και HR.</div>`);
  const F = (S.filters.assessRep ??= { q: "", ver: "", store: "", spec: "", search: "", from: "", to: "", state: "", group: "store" });
  const [qs, vers, atts] = await Promise.all([S.api.questionnaires(), S.api.versionsAll(), S.api.attempts()]);
  const qT = Object.fromEntries(qs.map((q) => [q.id, q])), vN = Object.fromEntries(vers.map((v) => [v.id, v.version]));
  // Εκκρεμείς: για επιλεγμένο ερωτηματολόγιο φέρνουμε και όσους δεν ξεκίνησαν
  const targets = F.q ? await S.api.assessmentTargets(F.q) : [];
  const stateOf = (a) => (a.status === "in_progress" && qT[a.questionnaire_id]?.ends_at && new Date(qT[a.questionnaire_id].ends_at) < new Date() ? "expired" : a.status);
  let rows = atts.map((a) => ({ ...a, state: stateOf(a), title: qT[a.questionnaire_id]?.title, version: vN[a.version_id] }));
  if (F.q) for (const t of targets.filter((t) => t.state === "not_started")) rows.push({ employee_code: t.employee_code, employee_name: t.employee_name, store: t.store, specialty: t.specialty, state: "not_started", questionnaire_id: F.q, title: qT[F.q]?.title, version: null });
  rows = rows.filter((r) => (!F.q || r.questionnaire_id === F.q) && (!F.ver || String(r.version) === F.ver) && (!F.store || r.store === F.store) && (!F.spec || r.specialty === F.spec) &&
    (!F.state || (F.state === "done" ? ["submitted", "pending_manual"].includes(r.state) : F.state === "open" ? ["not_started", "in_progress", "expired"].includes(r.state) : r.state === F.state)) &&
    (!F.search || norm(`${r.employee_name} ${r.employee_code}`).includes(norm(F.search))) &&
    (!F.from || (r.submitted_at || r.started_at || "").slice(0, 10) >= F.from) && (!F.to || (r.submitted_at || r.started_at || "9999").slice(0, 10) <= F.to));
  const verOpts = F.q ? vers.filter((v) => v.questionnaire_id === F.q && v.status !== "draft") : [];
  // Συγκεντρωτικά: μόνο μέσα στην ίδια έκδοση (συγκρίσιμοι κανόνες βαθμολόγησης)
  const graded = rows.filter((r) => r.state === "submitted" && pctOf(r) !== null);
  const groups = {};
  for (const r of rows) { const k = `${r.questionnaire_id}|${r.version ?? "—"}|${F.group === "store" ? r.store : F.group === "spec" ? r.specialty : r.employee_code}`; const g = (groups[k] ??= { title: r.title, version: r.version, key: F.group === "emp" ? r.employee_name : F.group === "store" ? r.store : r.specialty, n: 0, done: 0, open: 0, pcts: [] }); g.n++; if (["submitted", "pending_manual"].includes(r.state)) g.done++; else g.open++; if (graded.includes(r)) g.pcts.push(pctOf(r)); }
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Αξιολογήσεις</div><h1>Αναφορές αξιολογήσεων</h1>
    <p class="muted">Οι αριθμητικές βαθμολογίες συγκρίνονται μόνο μέσα στην ίδια έκδοση ερωτηματολογίου. Δεν συνδυάζονται με στατιστικά πωλήσεων ή αυτοαξιολόγηση σε ενιαίο βαθμό.</p></div>
    <button class="btn" id="rp-x">⇩ Excel</button></div>
  <div class="card"><div class="toolbar">
    <select id="rp-q"><option value="">Όλα τα ερωτηματολόγια</option>${qs.map((q) => `<option value="${q.id}" ${q.id === F.q ? "selected" : ""}>${h(q.title)}</option>`).join("")}</select>
    ${F.q ? `<select id="rp-ver"><option value="">Όλες οι εκδόσεις</option>${verOpts.map((v) => `<option ${String(v.version) === F.ver ? "selected" : ""}>${v.version}</option>`).join("")}</select>` : ""}
    <select id="rp-store"><option value="">Όλα τα καταστήματα</option>${visibleStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>
    <select id="rp-spec"><option value="">Όλες οι ειδικότητες</option>${activeSpecialties().map((s) => `<option ${s === F.spec ? "selected" : ""}>${h(s)}</option>`).join("")}</select>
    <select id="rp-state"><option value="">Κάθε κατάσταση</option><option value="done">Ολοκληρωμένες</option><option value="open">Εκκρεμείς</option>${Object.entries(ATTEMPT_STATE).map(([k, v]) => `<option value="${k}">${v.label}</option>`).join("")}</select>
    <input type="search" id="rp-s" placeholder="Εργαζόμενος" value="${h(F.search)}">
    <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Από <input type="date" id="rp-from" value="${F.from}" style="width:auto"></label>
    <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Έως <input type="date" id="rp-to" value="${F.to}" style="width:auto"></label>
  </div>
  ${F.q ? "" : `<p class="muted small" style="margin-bottom:10px">Επιλέξτε ερωτηματολόγιο για να εμφανιστούν και όσοι δεν έχουν ξεκινήσει.</p>`}
  <div class="tabs">${[["store", "Ανά κατάστημα"], ["spec", "Ανά ειδικότητα"], ["emp", "Ανά εργαζόμενο"]].map(([k, l]) => `<a href="javascript:void 0" data-g="${k}" class="${k === F.group ? "on" : ""}">${l}</a>`).join("")}</div>
  <div class="table-wrap"><table><thead><tr><th>Ερωτηματολόγιο · έκδοση</th><th>${{ store: "Κατάστημα", spec: "Ειδικότητα", emp: "Εργαζόμενος" }[F.group]}</th><th class="r">Σύνολο</th><th class="r">Ολοκληρωμένες</th><th class="r">Εκκρεμείς</th><th class="r">Μέσο % (βαθμολογημένες)</th></tr></thead><tbody>
    ${Object.values(groups).map((g) => `<tr><td>${h(g.title)} <span class="muted small">${g.version ? "v" + g.version : ""}</span></td><td>${h(g.key || "—")}</td><td class="r num">${g.n}</td><td class="r num">${g.done}</td><td class="r num">${g.open}</td><td class="r num">${g.pcts.length && g.version ? fmtP(g.pcts.reduce((s, x) => s + x, 0) / g.pcts.length) + ` <span class="muted small">(${g.pcts.length})</span>` : "—"}</td></tr>`).join("") || `<tr><td colspan="6" class="muted">Δεν υπάρχουν εγγραφές.</td></tr>`}
  </tbody></table></div>
  <h3 style="margin-top:18px">Αναλυτικά</h3>
  <div class="table-wrap" style="margin-top:8px"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Ερωτηματολόγιο</th><th>Κατάστημα · Ειδικότητα</th><th>Υποβολή</th><th>Κατάσταση</th><th class="r">Αποτέλεσμα</th></tr></thead><tbody>
    ${rows.map((r) => `<tr ${r.id ? `class="click" data-att="${h(r.id)}"` : ""}><td><strong>${h(r.employee_name)}</strong><span class="sub">${h(r.employee_code)}</span></td><td class="small">${h(r.title)}${r.version ? ` · v${r.version}` : ""}</td><td class="small">${h(r.store)} · ${h(r.specialty || "—")}</td>
      <td class="small">${r.submitted_at ? athens(r.submitted_at) : "—"}</td><td>${attemptBadge(r.state)}</td><td class="r num">${r.max_score ? `${num(r.score)} / ${num(r.max_score)}` : "—"}</td></tr>`).join("")}
  </tbody></table></div></div>`;
  $("#rp-state").value = F.state;
  const re = () => assessReports();
  for (const [id, k] of [["rp-q", "q"], ["rp-ver", "ver"], ["rp-store", "store"], ["rp-spec", "spec"], ["rp-state", "state"], ["rp-from", "from"], ["rp-to", "to"]]) $("#" + id) && ($("#" + id).onchange = (e) => { F[k] = e.target.value; if (k === "q") F.ver = ""; re(); });
  $("#rp-s").oninput = (e) => { F.search = e.target.value; re().then(() => { const i = $("#rp-s"); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }); };
  $$("[data-g]").forEach((b) => (b.onclick = () => { F.group = b.dataset.g; re(); }));
  $$("[data-att]").forEach((tr) => (tr.onclick = () => attemptDialog(tr.dataset.att)));
  $("#rp-x").onclick = () => downloadXlsx("Αξιολογήσεις.xlsx", { "Αξιολογήσεις": [["Κωδικός", "Εργαζόμενος", "Ερωτηματολόγιο", "Έκδοση", "Κατάστημα", "Ειδικότητα", "Άνοιξε", "Έναρξη", "Υποβολή", "Κατάσταση", "Βαθμοί", "Μέγιστο", "%"],
    ...rows.map((r) => [r.employee_code, r.employee_name, r.title, r.version ?? "", r.store, r.specialty || "", r.opened_by || "", r.started_at ? athens(r.started_at) : "", r.submitted_at ? athens(r.submitted_at) : "", ATTEMPT_STATE[r.state].label, r.score ?? "", r.max_score ?? "", pctOf(r) === null ? "" : Math.round(pctOf(r) * 10) / 10])] });
}
