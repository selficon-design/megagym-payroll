// Αναφορές ΓΔ / εκπαιδευτών προς κατάστημα και manager (έκδοση 3.1).
// Ορατότητα στον server (store_report_visible): ΓΔ όλες · εκπαιδευτής τις δικές του · manager του καταστήματός του.
// Καταγράφονται υποβολή, ανάγνωση, απαντήσεις, ανάληψη και ολοκλήρωση.
import { S, P, visibleStores, role } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, dmy, saveBlob } from "./util.js";
import { athens, athensToday, fileToPayload, base64ToBlob, demoNotice } from "./hr-common.js";

const view = () => $("#view");
const ST = { open: ["Ανοιχτή", "b-pending"], in_progress: ["Σε εξέλιξη", "b-info"], done: ["Ολοκληρώθηκε", "b-signed"] };
const ACT = { submitted: "Υποβολή", read: "Ανάγνωση", reply: "Απάντηση", claimed: "Ανάληψη", completed: "Ολοκλήρωση", attachment: "Συνημμένο" };
const ROLE = { owner: "ΓΔ", trainer: "Εκπαιδευτής", manager: "Manager", hr: "HR", accounting: "Λογιστήριο" };
const badge = (s) => `<span class="badge ${ST[s]?.[1] || ""}">${ST[s]?.[0] || h(s)}</span>`;

export async function storeReports(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αναφορές καταστημάτων"));
  if (params.get("id")) return reportView(params.get("id"));
  const F = (S.filters.srep ??= { store: "", status: "" });
  view().innerHTML = `<div class="empty"><div class="spinner"></div></div>`;
  let list;
  try { list = await S.api.srepList(F.store, F.status); }
  catch (e) { view().innerHTML = `<div class="card empty"><p><strong>Οι αναφορές δεν φόρτωσαν.</strong></p><p class="muted small">${h(e.message)}</p><button class="btn primary" id="sr-retry">Επανάληψη</button></div>`; $("#sr-retry").onclick = () => storeReports(params); return; }
  const canCreate = P("store_reports.create");
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Προσωπικό</div><h1>Αναφορές καταστημάτων</h1>
    <p class="muted">${role() === "manager" ? "Αναφορές της Γενικής Διεύθυνσης και των εκπαιδευτών προς το κατάστημά σας." : role() === "trainer" ? "Οι αναφορές που υποβάλατε προς καταστήματα και οι απαντήσεις τους." : "Όλες οι αναφορές προς καταστήματα."}</p></div>
    ${canCreate ? `<button class="btn primary" id="sr-new">+ Νέα αναφορά</button>` : ""}</div>
  <div class="card"><div class="toolbar">
      ${visibleStores().length > 1 ? `<select id="sr-store"><option value="">Όλα τα καταστήματα</option>${visibleStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>` : ""}
      <select id="sr-st"><option value="">Όλες οι καταστάσεις</option>${Object.entries(ST).map(([k, v]) => `<option value="${k}" ${k === F.status ? "selected" : ""}>${v[0]}</option>`).join("")}</select></div>
    ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Αναφορά</th><th>Κατάστημα</th><th>Από</th><th>Προθεσμία</th><th class="r">Απαντήσεις</th><th>Κατάσταση</th></tr></thead><tbody>
      ${list.map((r) => `<tr class="click ${r.unread ? "unread" : ""}" data-id="${r.id}"><td><strong>${h(r.subject)}</strong>${r.unread ? ` <span class="badge b-pending">νέο</span>` : ""}<span class="sub">${h(r.ref)}${r.action_required ? " · απαιτείται ενέργεια" : ""}</span></td>
        <td class="small">${h(r.store)}${r.manager_email ? `<span class="sub">${h(r.manager_email)}</span>` : ""}</td><td class="small">${h(r.created_by)}<span class="sub">${ROLE[r.created_role] || ""} · ${athens(r.created_at)}</span></td>
        <td class="small">${r.due_date ? dmy(r.due_date) : "—"}${r.overdue ? ` <span class="badge b-voided">καθυστέρηση</span>` : ""}</td><td class="r num">${r.replies}</td><td>${badge(r.status)}</td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty"><div class="big">✎</div>Δεν υπάρχουν αναφορές.</div>`}</div>`;
  $("#sr-store") && ($("#sr-store").onchange = (e) => { F.store = e.target.value; storeReports(new URLSearchParams()); });
  $("#sr-st").onchange = (e) => { F.status = e.target.value; storeReports(new URLSearchParams()); };
  $$("tr[data-id]").forEach((tr) => (tr.onclick = () => (location.hash = `#/store-reports?id=${tr.dataset.id}`)));
  $("#sr-new") && ($("#sr-new").onclick = newReport);
}

function newReport() {
  const stores = S.lists.stores.filter((s) => s.active !== false).map((s) => s.name);
  openDialog(`<div class="dlg-head"><h2>Νέα αναφορά προς κατάστημα</h2><button class="icon-btn" data-close>✕</button></div>
    <div class="grid g2"><div><label>Κατάστημα</label><select id="nr-s"><option value="">— επιλέξτε —</option>${stores.map((s) => `<option>${h(s)}</option>`).join("")}</select></div>
      <div><label>Αρμόδιος manager</label><select id="nr-m"><option value="">Όλοι οι managers του καταστήματος</option></select></div></div>
    <label>Θέμα</label><input id="nr-subj" maxlength="200">
    <label>Περιγραφή</label><textarea id="nr-d" rows="4" maxlength="8000"></textarea>
    <label>Παρατηρήσεις</label><textarea id="nr-o" rows="2" maxlength="4000"></textarea>
    <label class="check" style="margin-top:10px"><input type="checkbox" id="nr-act"> Απαιτείται ενέργεια από το κατάστημα (δημιουργείται εργασία για τον manager)</label>
    <div id="nr-actbox" hidden><label>Απαιτούμενες ενέργειες</label><textarea id="nr-ra" rows="2" maxlength="4000"></textarea></div>
    <div class="grid g2"><div><label>Προθεσμία (προαιρετικά)</label><input type="date" id="nr-due" min="${athensToday()}"></div>
      <div><label>Συνημμένα (PDF ή εικόνες έως 4 MB)</label><input type="file" id="nr-f" multiple accept=".pdf,.jpg,.jpeg,.png,.webp,.heic"></div></div>
    <p class="muted small">Δεν απαιτείται σύνδεση με εργαζόμενο. Ο manager λαμβάνει ειδοποίηση μέσα στην εφαρμογή.</p>
    <p id="nr-msg" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="nr-ok">Υποβολή</button></div>`, {
    wide: true,
    onOpen() {
      $("#nr-s").onchange = async (e) => {
        $("#nr-m").innerHTML = `<option value="">Όλοι οι managers του καταστήματος</option>`;
        if (!e.target.value) return;
        try { const m = await S.api.srepManagers(e.target.value); $("#nr-m").innerHTML += m.map((x) => `<option value="${h(x.email)}">${h(x.name)} · ${h(x.email)}</option>`).join(""); } catch { /* η επιλογή είναι προαιρετική */ }
      };
      $("#nr-act").onchange = (e) => ($("#nr-actbox").hidden = !e.target.checked);
      $("#nr-ok").onclick = async () => {
        const b = $("#nr-ok"); b.disabled = true;
        try {
          const files = []; for (const f of $("#nr-f").files) files.push(await fileToPayload(f));
          const r = await S.api.srepCreate({ store: $("#nr-s").value, manager_email: $("#nr-m").value || null, subject: $("#nr-subj").value, description: $("#nr-d").value,
            observations: $("#nr-o").value, action_required: $("#nr-act").checked, required_actions: $("#nr-ra").value, due_date: $("#nr-due").value || null, files });
          closeDialog(); toast(`Η αναφορά ${r.ref} υποβλήθηκε.`); location.hash = `#/store-reports?id=${r.id}`;
        } catch (e) { $("#nr-msg").textContent = e.message; b.disabled = false; }
      };
    },
  });
}

async function reportView(id) {
  let r;
  try { r = await S.api.srepGet(id); } catch (e) { return (view().innerHTML = `<div class="card empty">${h(e.message)} <a class="btn sm" href="#/store-reports">← Αναφορές</a></div>`); }
  window.dispatchEvent(new Event("mg:answers"));   // η ανάγνωση ενημερώνει τον μετρητή του μενού
  const files = r.events.filter((x) => x.file_name);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(r.ref)} · ${h(r.store)}</div><h1>${h(r.subject)}</h1>
    <p class="muted">${badge(r.status)} ${h(r.created_by)} (${ROLE[r.created_role] || ""}) · ${athens(r.created_at)}${r.due_date ? ` · προθεσμία ${dmy(r.due_date)}` : ""}</p></div>
    <a class="btn" href="#/store-reports">← Αναφορές</a></div>
  <div class="grid g2-1"><div>
    <div class="card"><h3>Αναφορά</h3>
      <dl class="kv"><dt>Κατάστημα</dt><dd>${h(r.store)}</dd><dt>Αρμόδιος manager</dt><dd>${h(r.manager_email || "Όλοι οι managers του καταστήματος")}</dd></dl>
      <h4 style="margin-top:12px">Περιγραφή</h4><div class="statement">${h(r.description)}</div>
      ${r.observations ? `<h4 style="margin-top:12px">Παρατηρήσεις</h4><p class="small" style="white-space:pre-wrap">${h(r.observations)}</p>` : ""}
      ${r.action_required ? `<h4 style="margin-top:12px">Απαιτούμενες ενέργειες</h4><p class="small" style="white-space:pre-wrap">${h(r.required_actions || "")}</p>` : ""}
      ${files.length ? `<h4 style="margin-top:12px">Συνημμένα</h4>${files.map((f) => `<div class="list-item small"><div class="grow">${h(f.file_name)}<div class="muted">${h(f.actor)} · ${athens(f.at)}</div></div><button class="btn sm" data-file="${h(f.id)}">Λήψη</button></div>`).join("")}` : ""}
      ${r.completion_note ? `<div class="note" style="margin-top:12px"><strong>Ολοκλήρωση:</strong> ${h(r.completion_note)}<br><span class="muted small">${h(r.completed_by)} · ${athens(r.completed_at)}</span></div>` : ""}
    </div>
    ${r.can_reply || r.can_respond ? `<div class="card" style="margin-top:16px"><h3>Απάντηση / ενέργεια</h3>
      <label>Κείμενο</label><textarea id="rv-n" rows="3" maxlength="4000"></textarea>
      <label>Αποδεικτικό / συνημμένο (προαιρετικά)</label><input type="file" id="rv-f" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic">
      <p id="rv-m" class="form-msg"></p>
      <div class="row-actions"><button class="btn" id="rv-reply">Απάντηση</button>
        ${r.can_respond && r.action_required && !r.claimed_by ? `<button class="btn" id="rv-claim">Αναλαμβάνω</button>` : ""}
        ${r.can_respond ? `<button class="btn primary" id="rv-done">Ολοκλήρωση με σχόλιο</button>` : ""}</div></div>` : ""}
  </div><div>
    <div class="card"><h3>Ιστορικό</h3>${r.events.slice().reverse().map((x) => `<div class="list-item small"><div class="grow"><strong>${ACT[x.action] || h(x.action)}</strong>${x.note ? `<div style="white-space:pre-wrap">${h(x.note)}</div>` : ""}${x.file_name ? `<div>📎 ${h(x.file_name)}</div>` : ""}<div class="muted">${h(x.actor)}${x.actor_role ? ` (${ROLE[x.actor_role] || x.actor_role})` : ""} · ${athens(x.at)}</div></div></div>`).join("")}</div>
  </div></div>`;
  $$("[data-file]").forEach((b) => (b.onclick = async () => { try { const f = await S.api.taskFile(b.dataset.file); saveBlob(base64ToBlob(f.data, f.mime), f.name); } catch (e) { toast(e.message, true); } }));
  const act = (action, ok) => async () => {
    try {
      const f = $("#rv-f")?.files[0] ? await fileToPayload($("#rv-f").files[0]) : null;
      await S.api.srepAct(r.id, action, $("#rv-n")?.value || "", f); toast(ok); reportView(id);
    } catch (e) { $("#rv-m").textContent = e.message; }
  };
  $("#rv-reply") && ($("#rv-reply").onclick = act("reply", "Η απάντηση καταχωρίστηκε."));
  $("#rv-claim") && ($("#rv-claim").onclick = act("claimed", "Αναλάβατε την ενέργεια."));
  $("#rv-done") && ($("#rv-done").onclick = act("completed", "Η αναφορά ολοκληρώθηκε."));
}
