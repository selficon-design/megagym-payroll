// Παρακολούθηση βελτίωσης & συνεργασίας (έκδοση 3.1). Όλοι οι κανόνες στον server (imp_*):
// στάδια 1–4, επανεξέταση με έκβαση και αιτιολογία, καμία αυτόματη ενέργεια λόγω προθεσμίας, στάδιο 3 μόνο μέσω της
// ροής έγγραφης προειδοποίησης, έντυπο σταδίου 2 μόνο όταν η ΓΔ ανεβάσει πρότυπο.
import { S, P, getEmployees, visibleStores } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, dmy, saveBlob } from "./util.js";
import { athens, athensToday, fileToPayload, base64ToBlob, demoNotice } from "./hr-common.js";

const view = () => $("#view");
export const SEVERITY = { minor: "Μικρής βαρύτητας", significant: "Σημαντική", critical: "Κρίσιμη / άμεσης κλιμάκωσης" };
export const STAGES = { 1: "Προφορική επισήμανση & σχέδιο δράσης", 2: "Επίσημη προφορική επισήμανση & πλάνο βελτίωσης", 3: "Έγγραφη προειδοποίηση HR", 4: "Εξέταση λύσης συνεργασίας" };
const OUTCOME = { complied: "Συμμορφώθηκε — κλείσιμο / διατήρηση συνεργασίας", partial: "Μερική βελτίωση — συνέχιση με νέα προθεσμία", back: "Επιστροφή σε προηγούμενο στάδιο", noncompliant: "Μη συμμόρφωση — εισήγηση επόμενου σταδίου" };
const ACT = { created: "Δημιουργία", updated: "Ενημέρωση", review: "Επανεξέταση", stage_change: "Αλλαγή σταδίου", note: "Σημείωση", attachment: "Συνημμένο", due_set: "Νέα προθεσμία",
  closed: "Κλείσιμο", warning_linked: "Σύνδεση αιτήματος έγγραφης προειδοποίησης", form_issued: "Έκδοση εντύπου σταδίου 2", form_printed: "Εκτύπωση εντύπου", signed_uploaded: "Υπογεγραμμένο έντυπο" };
const sevBadge = (s) => `<span class="badge ${s === "critical" ? "b-voided" : s === "significant" ? "b-pending" : "b-info"}">${SEVERITY[s]}</span>`;

export async function improvement(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Βελτίωση & συνεργασία"));
  if (params.get("id")) return caseView(Number(params.get("id")));
  const F = (S.filters.imp ??= { tab: "list", status: "open", store: "" });
  if (params.get("tab")) F.tab = params.get("tab");
  const emp = params.get("emp") || "";
  view().innerHTML = `<div class="empty"><div class="spinner"></div></div>`;
  let list, cfg, sum = null;
  try { [list, cfg] = await Promise.all([S.api.impList(emp || null), S.api.impSettings()]); if (F.tab === "summary" && P("improvement.summary")) sum = await S.api.impSummary(); }
  catch (e) { view().innerHTML = `<div class="card empty"><p><strong>Οι υποθέσεις δεν φόρτωσαν.</strong></p><p class="muted small">${h(e.message)}</p><button class="btn primary" id="im-retry">Επανάληψη</button></div>`; $("#im-retry").onclick = () => improvement(params); return; }
  const shown = list.filter((c) => (!F.status || c.status === F.status || (F.status === "overdue" && c.overdue)) && (!F.store || c.store === F.store));
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Προσωπικό</div><h1>Βελτίωση & συνεργασία</h1>
    <p class="muted">Υποθέσεις ανά εργαζόμενο, με στάδια, επανεξετάσεις και πλήρες ιστορικό. Καμία προειδοποίηση ή λύση συνεργασίας δεν γίνεται αυτόματα.</p></div>
    <div class="row-actions">${P("improvement.manage") ? `<button class="btn primary" id="im-new">+ Νέα υπόθεση</button>` : ""}</div></div>
  ${cfg && !cfg.day_mode ? `<div class="note warn" style="margin-bottom:12px">Οι προθεσμίες επανεξέτασης (15 / 7 / 7 ημέρες) ορίζονται χειροκίνητα: ο αυτόματος υπολογισμός θα ενεργοποιηθεί μόλις οριστεί αν είναι <strong>ημερολογιακές ή εργάσιμες</strong> ημέρες.${P("improvement.settings") ? ` <button class="btn sm" id="im-mode">Ορισμός</button>` : ""}</div>`
    : cfg ? `<p class="muted small" style="margin-bottom:12px">Αυτόματη πρόταση προθεσμίας: ${cfg.intervals.join(" / ")} ${cfg.day_mode === "working" ? "εργάσιμες" : "ημερολογιακές"} ημέρες.${P("improvement.settings") ? ` <a href="#" id="im-mode">Αλλαγή</a>` : ""}</p>` : ""}
  ${P("improvement.summary") ? `<div class="tabs"><a href="#/improvement?tab=list" class="${F.tab === "list" ? "on" : ""}">Υποθέσεις</a><a href="#/improvement?tab=summary" class="${F.tab === "summary" ? "on" : ""}">Συγκεντρωτικός πίνακας</a></div>` : ""}
  ${sum ? summaryHtml(sum) : `<div class="card">
    <div class="toolbar"><div class="chips">${[["open", "Ανοιχτές"], ["overdue", "Σε καθυστέρηση"], ["closed", "Κλειστές"], ["", "Όλες"]].map(([k, l]) => `<button class="chip ${F.status === k ? "on" : ""}" data-st="${k}">${l}<span class="n">${list.filter((c) => !k || c.status === k || (k === "overdue" && c.overdue)).length}</span></button>`).join("")}</div>
      ${visibleStores().length > 1 ? `<select id="im-store"><option value="">Όλα τα καταστήματα</option>${visibleStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>` : ""}
      ${emp ? `<span class="chip on">Εργαζόμενος ${h(emp)} <a href="#/improvement">✕</a></span>` : ""}</div>
    ${shown.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Υπόθεση</th><th>Εργαζόμενος</th><th>Βαρύτητα</th><th>Στάδιο</th><th>Υπεύθυνος</th><th>Επόμενη επανεξέταση</th><th>Κατάσταση</th></tr></thead><tbody>
      ${shown.map((c) => `<tr class="click" data-id="${c.id}"><td><strong>${h(c.incident_type)}</strong><span class="sub">${h(c.ref)} · ${dmy(c.incident_date)}</span></td>
        <td>${h(c.employee_name)}<span class="sub">${h(c.store)}${c.specialty ? " · " + h(c.specialty) : ""}</span></td><td>${sevBadge(c.severity)}</td>
        <td class="small">${c.stage}. ${h(c.stage_label)}${c.proposed_stage ? `<span class="sub">εισήγηση: στάδιο ${c.proposed_stage}</span>` : ""}</td><td class="small">${h(c.owner_email || "—")}</td>
        <td class="small">${c.next_review_due ? dmy(c.next_review_due) : "—"}${c.overdue ? ` <span class="badge b-voided">καθυστέρηση</span>` : ""}</td>
        <td>${c.status === "open" ? `<span class="badge b-pending">Ανοιχτή</span>` : `<span class="badge b-signed">Κλειστή</span>`}${c.last_outcome ? `<span class="sub">${h(OUTCOME[c.last_outcome].split(" — ")[0])}</span>` : ""}</td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty">Δεν υπάρχουν υποθέσεις${F.status ? " με αυτό το φίλτρο" : ""}.</div>`}</div>`}`;
  const re = () => improvement(params);
  $$("[data-st]").forEach((b) => (b.onclick = () => { F.status = b.dataset.st; re(); }));
  $("#im-store") && ($("#im-store").onchange = (e) => { F.store = e.target.value; re(); });
  $$("tr[data-id]").forEach((tr) => (tr.onclick = () => (location.hash = `#/improvement?id=${tr.dataset.id}`)));
  $$("[data-case]").forEach((tr) => (tr.onclick = () => (location.hash = `#/improvement?id=${tr.dataset.case}`)));
  $("#im-new") && ($("#im-new").onclick = () => newCase(emp));
  $("#im-mode") && ($("#im-mode").onclick = (e) => { e.preventDefault(); modeDialog(cfg, re); });
}

function summaryHtml(s) {
  const stageRow = [1, 2, 3, 4].map((k) => `<div class="card kpi"><div class="label">${k}. ${h(STAGES[k])}</div><div class="value num">${s.by_stage[k] || 0}</div></div>`).join("");
  return `<div class="grid g4">${stageRow}</div>
    <div class="card" style="margin-top:12px"><div class="chips"><span class="chip">Ανοιχτές<span class="n">${s.open}</span></span><span class="chip">Κλειστές<span class="n">${s.closed}</span></span><span class="chip">Σε καθυστέρηση<span class="n">${s.overdue}</span></span>
      ${Object.entries(OUTCOME).map(([k, l]) => `<span class="chip">${h(l.split(" — ")[0])}<span class="n">${s.by_outcome[k] || 0}</span></span>`).join("")}</div>
    <div class="table-wrap" style="margin-top:10px"><table class="stack"><thead><tr><th>Κατάστημα</th><th>Εργαζόμενος</th><th>Στάδιο</th><th>Υπεύθυνος</th><th>Τελευταία ενέργεια</th><th>Επόμενη επανεξέταση</th><th>Εξέλιξη</th></tr></thead><tbody>
    ${s.rows.map((r) => `<tr class="click" data-case="${r.id}"><td>${h(r.store)}</td><td>${h(r.employee_name)}<span class="sub">${h(r.ref)}</span></td><td class="small">${r.stage}. ${h(r.stage_label)}</td><td class="small">${h(r.owner || "—")}</td>
      <td class="small">${h(ACT[r.last_action] || r.last_action || "—")}<span class="sub">${athens(r.last_action_at)}</span></td><td class="small">${r.next_review_due ? dmy(r.next_review_due) : "—"}${r.overdue ? ` <span class="badge b-voided">καθυστέρηση</span>` : ""}</td>
      <td class="small">${r.status === "closed" ? "Κλειστή" : "Ανοιχτή"}${r.last_outcome ? ` · ${h(OUTCOME[r.last_outcome].split(" — ")[0])}` : ""}${r.proposed_stage ? ` · εισήγηση σταδίου ${r.proposed_stage}` : ""}</td></tr>`).join("") || `<tr><td colspan="7" class="muted">Καμία υπόθεση.</td></tr>`}
    </tbody></table></div></div>`;
}

function modeDialog(cfg, reload) {
  openDialog(`<div class="dlg-head"><h2>Προθεσμίες επανεξέτασης</h2><button class="icon-btn" data-close>✕</button></div>
    <p>Διαστήματα επανεξέτασης μεταξύ των σταδίων: <strong>${cfg.intervals.join(" / ")} ημέρες</strong>. Ορίστε τι είδους ημέρες είναι, ώστε να ενεργοποιηθεί η αυτόματη πρόταση προθεσμίας. Η προθεσμία μπορεί πάντα να αλλάξει χειροκίνητα.</p>
    <div class="chips"><label class="chip"><input type="radio" name="dm" value="calendar" ${cfg.day_mode === "calendar" ? "checked" : ""}> Ημερολογιακές</label><label class="chip"><input type="radio" name="dm" value="working" ${cfg.day_mode === "working" ? "checked" : ""}> Εργάσιμες (Δευτέρα–Παρασκευή, χωρίς αργίες)</label><label class="chip"><input type="radio" name="dm" value="" ${!cfg.day_mode ? "checked" : ""}> Χωρίς αυτόματο υπολογισμό</label></div>
    <p id="dm-m" class="form-msg"></p><div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="dm-ok">Αποθήκευση</button></div>`, {
    onOpen() { $("#dm-ok").onclick = async () => { try { await S.api.impSetDayMode($("input[name=dm]:checked")?.value || null); closeDialog(); toast("Αποθηκεύτηκε."); reload(); } catch (e) { $("#dm-m").textContent = e.message; } }; },
  });
}

async function newCase(code) {
  const emps = (await getEmployees()).filter((e) => e.status === "Ενεργός" && visibleStores().includes(e.store));
  openDialog(`<div class="dlg-head"><h2>Νέα υπόθεση βελτίωσης</h2><button class="icon-btn" data-close>✕</button></div>
    <div class="grid g2"><div><label>Εργαζόμενος</label><select id="nc-e"><option value="">— επιλέξτε —</option>${emps.map((e) => `<option value="${h(e.code)}" ${e.code === code ? "selected" : ""}>${h(e.last)} ${h(e.first)} · ${h(e.store)}</option>`).join("")}</select></div>
      <div><label>Βαρύτητα</label><select id="nc-s"><option value="">— επιλέξτε —</option>${Object.entries(SEVERITY).map(([k, l]) => `<option value="${k}">${l}</option>`).join("")}</select></div>
      <div><label>Είδος περιστατικού</label><input id="nc-t" maxlength="200"></div><div><label>Ημερομηνία περιστατικού</label><input type="date" id="nc-d" max="${athensToday()}"></div></div>
    <label>Περιγραφή</label><textarea id="nc-desc" rows="3" maxlength="8000"></textarea>
    <label>Τεκμηρίωση</label><textarea id="nc-doc" rows="2" maxlength="4000"></textarea>
    <label>Ενέργειες (σχέδιο δράσης)</label><textarea id="nc-act" rows="2" maxlength="4000"></textarea>
    <div class="grid g2"><div><label>Υπεύθυνος (email· κενό = εσείς)</label><input id="nc-o" type="email"></div><div><label>Προθεσμία επανεξέτασης</label><input type="date" id="nc-due" min="${athensToday()}"></div></div>
    <label>Παρατηρήσεις</label><textarea id="nc-n" rows="2" maxlength="4000"></textarea>
    <p class="muted small">Η υπόθεση ξεκινά στο στάδιο 1 «${STAGES[1]}».</p><p id="nc-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="nc-ok">Καταχώριση</button></div>`, {
    wide: true,
    onOpen() {
      $("#nc-ok").onclick = async () => {
        try {
          const r = await S.api.impCreate({ employee_code: $("#nc-e").value, severity: $("#nc-s").value, incident_type: $("#nc-t").value, incident_date: $("#nc-d").value,
            description: $("#nc-desc").value, documentation: $("#nc-doc").value, actions: $("#nc-act").value, owner_email: $("#nc-o").value.trim().toLowerCase(), next_review_due: $("#nc-due").value, notes: $("#nc-n").value });
          closeDialog(); toast(`Η υπόθεση ${r.ref} καταχωρίστηκε.`); location.hash = `#/improvement?id=${r.id}`;
        } catch (e) { $("#nc-m").textContent = e.message; }
      };
    },
  });
}

async function caseView(id) {
  let c;
  try { c = await S.api.impGet(id); } catch (e) { return (view().innerHTML = `<div class="card empty">${h(e.message)} <a class="btn sm" href="#/improvement">← Υποθέσεις</a></div>`); }
  const open = c.status === "open", m = c.can_manage && open;
  const tpl = c.stage === 2 ? (await S.api.impSettings().catch(() => null))?.template : null;
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(c.ref)} · ${h(c.store)}</div><h1>${h(c.employee_name)} — ${h(c.incident_type)}</h1>
    <p class="muted">${sevBadge(c.severity)} Στάδιο ${c.stage}: <strong>${h(c.stage_label)}</strong> · ${open ? `<span class="badge b-pending">Ανοιχτή</span>` : `<span class="badge b-signed">Κλειστή</span>`}
      ${c.next_review_due ? ` · επόμενη επανεξέταση ${dmy(c.next_review_due)}${open && c.next_review_due < athensToday() ? ` <span class="badge b-voided">καθυστέρηση</span>` : ""}` : ""}</p></div>
    <div class="row-actions"><a class="btn" href="#/employee?code=${encodeURIComponent(c.employee_code)}">Καρτέλα</a><a class="btn" href="#/improvement">← Υποθέσεις</a></div></div>
  <div class="grid g2-1"><div>
    <div class="card"><h3>Υπόθεση</h3><dl class="kv"><dt>Εργαζόμενος</dt><dd>${h(c.employee_name)} · ${h(c.employee_code)} · ${h(c.store)}${c.specialty ? " · " + h(c.specialty) : ""}</dd>
      <dt>Ημερομηνία περιστατικού</dt><dd>${dmy(c.incident_date)}</dd><dt>Υπεύθυνος</dt><dd>${h(c.owner_email || "—")}</dd>
      ${c.proposed_stage ? `<dt>Εισήγηση</dt><dd>Μετάβαση στο στάδιο ${c.proposed_stage} (${h(STAGES[c.proposed_stage])}) — απαιτεί ενέργεια χρήστη</dd>` : ""}
      ${c.warning_ref ? `<dt>Έγγραφη προειδοποίηση</dt><dd><a href="#/request?id=${h(c.warning_request_id)}">${h(c.warning_ref)}</a> (${h(c.warning_status)})</dd>` : ""}</dl>
      <h4 style="margin-top:10px">Περιγραφή</h4><div class="statement">${h(c.description)}</div>
      ${c.documentation ? `<h4 style="margin-top:10px">Τεκμηρίωση</h4><p class="small" style="white-space:pre-wrap">${h(c.documentation)}</p>` : ""}
      ${c.actions ? `<h4 style="margin-top:10px">Ενέργειες</h4><p class="small" style="white-space:pre-wrap">${h(c.actions)}</p>` : ""}
      ${c.notes ? `<h4 style="margin-top:10px">Παρατηρήσεις</h4><p class="small" style="white-space:pre-wrap">${h(c.notes)}</p>` : ""}</div>
    ${c.stage === 2 ? `<div class="card" style="margin-top:16px"><h3>Έντυπο σταδίου 2</h3>
      ${tpl ? `<p class="small">Πρότυπο έκδοσης ${tpl.version} (${h(tpl.pdf_name)}).</p>` : `<div class="note warn">Δεν έχει προστεθεί πρότυπο. Η έκδοση εντύπου θα ενεργοποιηθεί όταν η Γενική Διεύθυνση ανεβάσει το PDF στα «Πρότυπα κειμένων».</div>`}
      ${c.forms.map((f) => `<div class="list-item small"><div class="grow">Έντυπο (πρότυπο v${f.version}) · ${h(f.issued_by)} · ${athens(f.issued_at)} · εκτυπώσεις ${f.print_count} ${f.signed ? `<span class="badge b-signed">Υπογεγραμμένο αντίγραφο</span>` : `<span class="badge b-missing">χωρίς υπογεγραμμένο αντίγραφο</span>`}</div>
        ${c.can_print ? `<button class="btn sm" data-print="${f.id}">Εκτύπωση</button>` : ""}${c.can_print && !f.signed ? `<label class="btn sm" style="margin:0">Υπογεγραμμένο…<input type="file" data-signed="${f.id}" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic" hidden></label>` : ""}</div>`).join("")}
      ${m ? `<button class="btn" id="cv-issue" ${tpl ? "" : "disabled"} style="margin-top:8px">Έκδοση εντύπου</button>` : ""}
      <p class="muted small" style="margin-top:6px">Η εκτύπωση καταγράφεται αλλά δεν θεωρείται παράδοση ή υπογραφή· επισυνάψτε τη σάρωση ή φωτογραφία του υπογεγραμμένου εντύπου.</p></div>` : ""}
    ${m ? `<div class="card" style="margin-top:16px"><h3>Ενέργειες</h3><div class="row-actions">
      <button class="btn primary" id="cv-review">Επανεξέταση</button><button class="btn" id="cv-stage">Αλλαγή σταδίου</button>
      ${c.stage === 2 && !c.warning_request_id ? `<button class="btn" id="cv-warn">Σύνδεση αιτήματος έγγραφης προειδοποίησης</button>` : ""}<button class="btn" id="cv-note">Σημείωση / συνημμένο</button><button class="btn ghost" id="cv-edit">Υπεύθυνος & προθεσμία</button></div></div>` : ""}
  </div><div>
    <div class="card"><h3>Ιστορικό</h3>${c.events.slice().reverse().map((x) => `<div class="list-item small"><div class="grow"><strong>${ACT[x.action] || h(x.action)}</strong>${x.outcome ? ` · ${h(OUTCOME[x.outcome])}` : ""}${x.from_stage && x.to_stage && x.from_stage !== x.to_stage ? ` · στάδιο ${x.from_stage} → ${x.to_stage}` : ""}
      ${x.reason ? `<div style="white-space:pre-wrap">${h(x.reason)}</div>` : ""}${x.action_date ? `<div>Ημερομηνία ενέργειας: ${dmy(x.action_date)}</div>` : ""}${x.due_date ? `<div>Προθεσμία: ${dmy(x.due_date)}</div>` : ""}
      ${x.file_name ? `<div><a href="#" data-file="${x.id}">📎 ${h(x.file_name)}</a></div>` : ""}<div class="muted">${h(x.actor)} · ${athens(x.at)}</div></div></div>`).join("")}</div>
  </div></div>`;
  const re = () => caseView(id);
  const run = (fn, ok) => async () => { try { await fn(); closeDialog(); toast(ok); re(); } catch (e) { ($("#dx-m") || {}).textContent = e.message; if (!$("#dx-m")) toast(e.message, true); } };
  $$("[data-file]").forEach((a) => (a.onclick = async (e) => { e.preventDefault(); try { const f = await S.api.impFile(Number(a.dataset.file)); saveBlob(base64ToBlob(f.data, f.mime), f.name); } catch (err) { toast(err.message, true); } }));
  $$("[data-print]").forEach((b) => (b.onclick = async () => {
    try { const f = await S.api.impFormPrint(Number(b.dataset.print)); const url = URL.createObjectURL(base64ToBlob(f.data, "application/pdf")); const w = window.open(url, "_blank"); if (!w) saveBlob(base64ToBlob(f.data, "application/pdf"), f.name); toast("Η εκτύπωση καταγράφηκε."); re(); }
    catch (e) { toast(e.message, true); }
  }));
  $$("[data-signed]").forEach((inp) => (inp.onchange = async () => { const f = inp.files[0]; if (!f) return; try { await S.api.impNote(c.id, "Υπογεγραμμένο έντυπο σταδίου 2", await fileToPayload(f), "signed_uploaded", Number(inp.dataset.signed)); toast("Επισυνάφθηκε."); re(); } catch (e) { toast(e.message, true); } }));
  $("#cv-issue") && ($("#cv-issue").onclick = run(() => S.api.impIssueForm(c.id), "Το έντυπο εκδόθηκε."));
  $("#cv-review") && ($("#cv-review").onclick = () => openDialog(`<div class="dlg-head"><h2>Επανεξέταση</h2><button class="icon-btn" data-close>✕</button></div>
    <label>Έκβαση</label>${Object.entries(OUTCOME).map(([k, l]) => `<label class="check"><input type="radio" name="rv-o" value="${k}" ${k === "back" && c.stage === 1 ? "disabled" : ""}> ${h(l)}</label>`).join("")}
    <div class="grid g2"><div><label>Ημερομηνία επανεξέτασης (πραγματική)</label><input type="date" id="rv-d" value="${athensToday()}" max="${athensToday()}"></div><div><label>Νέα προθεσμία (υποχρεωτική στη μερική βελτίωση)</label><input type="date" id="rv-due"></div></div>
    <label>Αιτιολογία</label><textarea id="rv-r" rows="3" maxlength="4000"></textarea>
    <p class="muted small">Η «Μη συμμόρφωση» καταγράφει εισήγηση επόμενου σταδίου· η μετάβαση γίνεται χωριστά με «Αλλαγή σταδίου».</p><p id="dx-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="rv-ok">Καταχώριση</button></div>`, {
    onOpen() { $("#rv-ok").onclick = run(() => S.api.impReview(c.id, $("input[name=rv-o]:checked")?.value || "", $("#rv-r").value, $("#rv-d").value || null, $("#rv-due").value || null, c.version), "Η επανεξέταση καταχωρίστηκε."); },
  }));
  $("#cv-stage") && ($("#cv-stage").onclick = () => openDialog(`<div class="dlg-head"><h2>Αλλαγή σταδίου</h2><button class="icon-btn" data-close>✕</button></div>
    <label>Νέο στάδιο</label><select id="st-s">${[1, 2, 3, 4].filter((k) => k !== c.stage && k <= c.stage + 1).map((k) => `<option value="${k}" ${k === c.proposed_stage ? "selected" : ""}>${k}. ${h(STAGES[k])}</option>`).join("")}</select>
    <p class="muted small">Στάδιο 3: απαιτείται συνδεδεμένο αίτημα έγγραφης προειδοποίησης (Manager → προσχέδιο HR → τελική έγκριση ΓΔ → κοινοποίηση HR). Στάδιο 4: μόνο ΓΔ ή HR· δεν αλλάζει την κατάσταση του εργαζομένου.</p>
    <label>Προθεσμία επανεξέτασης ${c.suggest_enabled ? "(κενό = αυτόματη πρόταση)" : ""}</label><input type="date" id="st-due"><label>Αιτιολογία</label><textarea id="st-r" rows="3" maxlength="4000"></textarea><p id="dx-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="st-ok">Αλλαγή</button></div>`, {
    onOpen() { $("#st-ok").onclick = run(() => S.api.impSetStage(c.id, Number($("#st-s").value), $("#st-r").value, $("#st-due").value || null, c.version), "Το στάδιο άλλαξε."); },
  }));
  $("#cv-warn") && ($("#cv-warn").onclick = async () => {
    const reqs = (await S.api.requests({ employee: c.employee_code }).catch(() => [])).filter((r) => r.category === "warning_request");
    openDialog(`<div class="dlg-head"><h2>Αίτημα έγγραφης προειδοποίησης</h2><button class="icon-btn" data-close>✕</button></div>
      ${reqs.length ? `<label>Υπάρχον αίτημα</label><select id="wr-s">${reqs.map((r) => `<option value="${r.id}">${h(r.ref)} · ${athens(r.created_at)}</option>`).join("")}</select>` : `<p class="muted">Δεν υπάρχει αίτημα έγγραφης προειδοποίησης για τον εργαζόμενο.</p>`}
      <p><a href="#/request-new?kind=manager&code=${encodeURIComponent(c.employee_code)}">+ Νέο αίτημα έγγραφης προειδοποίησης</a> (επιλέξτε κατηγορία «Αίτημα έγγραφης προειδοποίησης») και επιστρέψτε εδώ για σύνδεση.</p><p id="dx-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button>${reqs.length ? `<button class="btn primary" id="wr-ok">Σύνδεση</button>` : ""}</div>`, {
      onOpen() { $("#wr-ok") && ($("#wr-ok").onclick = run(() => S.api.impLinkWarning(c.id, $("#wr-s").value, c.version), "Συνδέθηκε.")); },
    });
  });
  $("#cv-note") && ($("#cv-note").onclick = () => openDialog(`<div class="dlg-head"><h2>Σημείωση / συνημμένο</h2><button class="icon-btn" data-close>✕</button></div>
    <label>Σημείωση</label><textarea id="nt-t" rows="3" maxlength="4000"></textarea><label>Συνημμένο (PDF ή εικόνα έως 4 MB)</label><input type="file" id="nt-f" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic"><p id="dx-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="nt-ok">Καταχώριση</button></div>`, {
    onOpen() { $("#nt-ok").onclick = run(async () => S.api.impNote(c.id, $("#nt-t").value, $("#nt-f").files[0] ? await fileToPayload($("#nt-f").files[0]) : null, "note", null), "Καταχωρίστηκε."); },
  }));
  $("#cv-edit") && ($("#cv-edit").onclick = () => openDialog(`<div class="dlg-head"><h2>Υπεύθυνος & προθεσμία</h2><button class="icon-btn" data-close>✕</button></div>
    <div class="grid g2"><div><label>Υπεύθυνος (email)</label><input id="ed-o" type="email" value="${h(c.owner_email || "")}"></div><div><label>Προθεσμία επανεξέτασης</label><input type="date" id="ed-due" value="${h(c.next_review_due || "")}"></div></div>
    <label>Ενέργειες</label><textarea id="ed-a" rows="2">${h(c.actions || "")}</textarea><label>Αιτιολογία αλλαγής</label><input id="ed-r" maxlength="500"><p id="dx-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="ed-ok">Αποθήκευση</button></div>`, {
    onOpen() { $("#ed-ok").onclick = run(() => S.api.impUpdate(c.id, { owner_email: $("#ed-o").value.trim().toLowerCase(), next_review_due: $("#ed-due").value || null, actions: $("#ed-a").value, reason: $("#ed-r").value }, c.version), "Αποθηκεύτηκε."); },
  }));
}

// Ενότητα στην καρτέλα εργαζομένου
export async function cardImprovement(e, body) {
  const list = await S.api.impList(e.code);
  body.innerHTML = `<div class="card"><div class="card-head"><h3>Βελτίωση & συνεργασία</h3>${P("improvement.manage") ? `<a class="btn sm primary" href="#/improvement?emp=${encodeURIComponent(e.code)}">Υποθέσεις / νέα υπόθεση</a>` : ""}</div>
    ${list.length ? list.map((c) => `<div class="list-item"><div class="grow"><a href="#/improvement?id=${c.id}"><strong>${h(c.incident_type)}</strong></a> · ${h(c.ref)}<div class="muted small">Στάδιο ${c.stage}: ${h(c.stage_label)} · ${c.status === "open" ? "ανοιχτή" : "κλειστή"}${c.next_review_due ? ` · επανεξέταση ${dmy(c.next_review_due)}` : ""}</div></div>${sevBadge(c.severity)}</div>`).join("") : `<p class="muted small">Καμία υπόθεση.</p>`}</div>`;
}
