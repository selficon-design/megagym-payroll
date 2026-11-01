// Ενιαία καρτέλα εργαζομένου: ίδιος κωδικός σε όλες τις ενότητες.
// Κάθε καρτέλα φορτώνεται χωριστά και ο server επιστρέφει μόνο ό,τι επιτρέπεται στον ρόλο.
import { S, can, role, specialtyKind } from "./core.js";
import { $, $$, h, dmy, money, monthLabel, badge, toast, openDialog } from "./util.js";
import { CATEGORIES, flowOf, reqBadge, attemptBadge, athens, daysWord, demoNotice } from "./hr-common.js";
import { KINDS, FIELD_SHORT, totals, metrics, fmtPct, warnings } from "./stats-calc.js";
import { viewDeclaration } from "./views-main.js";
import { attemptDialog } from "./views-assess.js";

const view = () => $("#view");

export async function employeeCard(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Καρτέλα εργαζομένου"));
  const code = params.get("code");
  const tab = params.get("tab") || (role() === "trainer" ? "assess" : "info");
  let e;
  if (role() === "trainer") e = (await S.api.trainerEmployees()).find((x) => x.code === code);
  else e = await S.api.employee(code);
  if (!e) return (view().innerHTML = `<div class="card empty">Ο εργαζόμενος δεν βρέθηκε ή δεν ανήκει στο πεδίο σας.</div>`);

  const TABS = [
    ["info", "Στοιχεία", role() !== "trainer"],
    ["payroll", "Μισθοδοσία", can.payroll()],
    ["requests", "Αιτήματα & αποφάσεις", can.requests()],
    ["leave", "Άδειες", can.requests()],
    ["reports", "Αναφορές & προειδοποιήσεις", can.requests()],
    ["stats", "Ημερήσια στατιστικά", ["owner", "hr", "manager"].includes(role())],
    ["assess", "Αξιολογήσεις", can.assessOpen()],
  ].filter((t) => t[2]);
  const t = TABS.some((x) => x[0] === tab) ? tab : TABS[0][0];

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Καρτέλα εργαζομένου · ${h(e.code)}</div><h1>${h(e.first)} ${h(e.last)}</h1>
    <p class="muted">${h(e.specialty || "Χωρίς ειδικότητα")} · ${h(e.store)} · ${h(e.company)} · <span class="badge ${e.status === "Ενεργός" ? "b-signed" : "b-missing"}">${h(e.status)}</span></p></div>
    <div class="row-actions">${can.createRequests() && e.status === "Ενεργός" ? `<a class="btn" href="#/request-new?kind=manager&code=${encodeURIComponent(e.code)}">+ Αναφορά</a><a class="btn primary" href="#/request-new?kind=employee&code=${encodeURIComponent(e.code)}">+ Αίτημα</a>` : ""}</div></div>
  <div class="tabs">${TABS.map(([k, l]) => `<a href="#/employee?code=${encodeURIComponent(code)}&tab=${k}" class="${k === t ? "on" : ""}">${l}</a>`).join("")}</div>
  <div id="card-body"><div class="empty"><div class="spinner"></div></div></div>`;
  const body = $("#card-body");
  try { await ({ info, payroll, requests: reqs, leave, reports, stats, assess })[t](e, body, params); }
  catch (err) { body.innerHTML = `<div class="card note bad">${h(err.message)}</div>`; }
}

async function info(e, body) {
  const asg = await S.api.assignments(e.code);
  body.innerHTML = `<div class="grid g2">
    <div class="card"><h3>Βασικά στοιχεία</h3><dl class="kv">
      <dt>Κωδικός</dt><dd>${h(e.code)}</dd><dt>Ονοματεπώνυμο</dt><dd>${h(e.first)} ${h(e.last)}</dd>
      <dt>Ειδικότητα</dt><dd>${h(e.specialty || "—")}</dd><dt>Κατάστημα</dt><dd>${h(e.store)}</dd><dt>Εταιρεία</dt><dd>${h(e.company)}</dd>
      <dt>Ημ. πρόσληψης</dt><dd>${e.hire_date ? dmy(e.hire_date) : "—"}</dd><dt>Κατάσταση</dt><dd>${h(e.status)}</dd></dl>
      ${!e.specialty || !e.hire_date ? `<p class="muted small" style="margin-top:12px">${can.editEmployees() ? "Συμπληρώστε ειδικότητα και ημερομηνία πρόσληψης από «Εργαζόμενοι → Επεξεργασία»." : "Λείπουν στοιχεία· τα συμπληρώνει το HR."}</p>` : ""}
    </div>
    <div class="card"><h3>Ιστορικό θέσης</h3><p class="muted small">Ο κωδικός μένει ίδιος· κάθε παλιά εγγραφή κρατά το κατάστημα και την ειδικότητα της περιόδου της.</p>
      <div class="table-wrap" style="margin-top:10px"><table><thead><tr><th>Από</th><th>Έως</th><th>Κατάστημα</th><th>Ειδικότητα</th></tr></thead><tbody>
      ${asg.map((a) => `<tr><td class="small">${athens(a.valid_from, false)}</td><td class="small">${a.valid_to ? athens(a.valid_to, false) : "σήμερα"}</td><td>${h(a.store)}</td><td>${h(a.specialty || "—")}</td></tr>`).join("")}
      </tbody></table></div></div></div>`;
}

async function payroll(e, body) {
  const ds = await S.api.declarations({});
  const mine = ds.filter((d) => d.employee_code === e.code);
  body.innerHTML = `<div class="card">${mine.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Μήνας</th><th>Κατάστημα</th><th class="r">Ποσό</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
    ${mine.map((d) => `<tr><td>${h(monthLabel(d.month))}</td><td data-l="Κατάστημα">${h(d.store)}</td><td class="r num">${money(d.amount)}</td><td>${badge(d.status)}${d.signed_at ? `<span class="sub">${athens(d.signed_at)}</span>` : ""}</td>
      <td style="text-align:right">${d.status !== "pending" ? `<button class="btn sm" data-view="${h(d.id)}">Προβολή / PDF</button>` : ""}</td></tr>`).join("")}</tbody></table></div>`
    : `<div class="empty">Δεν υπάρχουν δηλώσεις μισθοδοσίας${role() === "manager" ? " στο κατάστημά σας" : ""}.</div>`}</div>`;
  $$("[data-view]", body).forEach((b) => (b.onclick = () => viewDeclaration(b.dataset.view)));
}

async function loadReqs(e) {
  const list = await S.api.requests({ employee: e.code });
  const visible = list.filter((x) => x.status !== "draft" || x.created_by === S.me.email);
  const dec = await S.api.decisionsFor(visible.map((x) => x.id));
  const cur = Object.fromEntries(dec.map((d) => [d.request_id, d]));
  return { visible, cur };
}
const reqTable = (rows, cur, extra = () => "") => rows.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Αριθμός</th><th>Κατηγορία</th><th>Κατάστημα</th><th>Κατάσταση</th><th>Απόφαση</th></tr></thead><tbody>
  ${rows.map((x) => `<tr class="click" data-id="${h(x.id)}"><td class="num"><strong>${h(x.ref)}</strong><span class="sub">${athens(x.submitted_at || x.created_at, false)}</span></td>
    <td>${h(CATEGORIES[x.category])}${extra(x)}</td><td data-l="Κατάστημα">${h(x.store)}</td><td>${reqBadge(x.status)}</td>
    <td class="small" data-l="Απόφαση">${cur[x.id] ? `${{ approve: "Έγκριση", reject: "Απόρριψη", needs_info: "Διευκρινίσεις" }[cur[x.id].outcome]} · ${h(cur[x.id].decided_by)} · ${athens(cur[x.id].decided_at, false)}` : "—"}</td></tr>`).join("")}
  </tbody></table></div>` : `<div class="empty">Δεν υπάρχουν εγγραφές.</div>`;
const bindRows = (body) => $$("tr.click", body).forEach((tr) => (tr.onclick = () => (location.hash = `#/request?id=${tr.dataset.id}`)));

async function reqs(e, body) {
  const { visible, cur } = await loadReqs(e);
  body.innerHTML = `<div class="card">${reqTable(visible.filter((x) => x.process === "employee" && x.category !== "leave"), cur)}</div>`;
  bindRows(body);
}
async function leave(e, body) {
  const { visible, cur } = await loadReqs(e);
  const rows = visible.filter((x) => x.category === "leave");
  const approved = rows.filter((x) => ["approved", "completed"].includes(x.status) && cur[x.id]?.outcome === "approve");
  body.innerHTML = `<div class="card"><div class="card-head"><h3>Εγκεκριμένες άδειες</h3></div>
    ${approved.length ? approved.map((x) => `<div class="list-item"><div class="grow"><strong>${h(x.leave_type_label)}</strong> · ${dmy(cur[x.id].approved_start || x.start_date)} – ${dmy(cur[x.id].approved_end || x.end_date)} · ${daysWord(cur[x.id].approved_days || x.days_requested)} ημέρες</div><span class="muted small">${h(x.ref)}</span></div>`).join("") : `<p class="muted">Καμία εγκεκριμένη άδεια.</p>`}
    <p class="muted small" style="margin-top:10px">Δεν εμφανίζεται υπόλοιπο: δεν υπάρχει αξιόπιστη πηγή δικαιούμενων ημερών.</p></div>
    <div class="card" style="margin-top:16px"><div class="card-head"><h3>Όλες οι αιτήσεις άδειας</h3></div>${reqTable(rows, cur, (x) => `<span class="sub">${h(x.leave_type_label || "")} · ${dmy(x.start_date)} – ${dmy(x.end_date)}</span>`)}</div>`;
  bindRows(body);
}
async function reports(e, body) {
  const { visible, cur } = await loadReqs(e);
  const rows = visible.filter((x) => x.process === "manager");
  const warnings_ = rows.filter((x) => x.category === "warning_request" && ["approved", "completed"].includes(x.status) && cur[x.id]?.outcome === "approve");
  body.innerHTML = `<div class="card"><div class="card-head"><h3>Εγκεκριμένες έγγραφες προειδοποιήσεις</h3></div>
    ${warnings_.length ? warnings_.map((x) => `<div class="list-item"><div class="grow"><strong>${h(x.ref)}</strong> · εγκρίθηκε ${athens(cur[x.id].decided_at, false)} από ${h(cur[x.id].decided_by)}${x.status === "completed" ? ` · κοινοποιήθηκε ${athens(x.notified_at, false)}` : " · <span class='badge b-pending'>αναμένεται κοινοποίηση</span>"}</div><a class="btn sm" href="#/request?id=${h(x.id)}">Άνοιγμα</a></div>`).join("")
      : `<p class="muted">Καμία εγκεκριμένη προειδοποίηση. Οι αναφορές manager δεν αποτελούν από μόνες τους προειδοποίηση.</p>`}</div>
    <div class="card" style="margin-top:16px"><div class="card-head"><h3>Αναφορές manager</h3></div>${reqTable(rows, cur, (x) => x.incident_date ? `<span class="sub">Περιστατικό ${dmy(x.incident_date)}</span>` : "")}</div>`;
  bindRows(body);
}

async function stats(e, body, params) {
  const today = new Date(); const from0 = new Date(today.getTime() - 89 * 86400000);
  const from = params.get("from") || from0.toISOString().slice(0, 10), to = params.get("to") || today.toISOString().slice(0, 10);
  const rows = await S.api.stats({ from, to, employee: e.code });
  const kinds = [...new Set(rows.map((r) => r.kind))];
  body.innerHTML = `<div class="card"><div class="toolbar">
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Από <input type="date" id="cs-from" value="${from}" style="width:auto"></label>
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Έως <input type="date" id="cs-to" value="${to}" style="width:auto"></label>
      <span class="muted small">${rows.length} ημέρες με καταχώριση${role() === "manager" ? " στο κατάστημά σας" : ""}</span></div>
    ${kinds.length ? kinds.map((k) => { const t = totals(rows, k), m = metrics(t, k), w = warnings(t, k);
      return `<h3 style="margin-top:12px">${KINDS[k].label}</h3>
      <div class="table-wrap" style="margin-top:8px"><table><thead><tr>${k !== "exclusive" ? "<th class='r'>Ενημερώσεις</th>" : ""}${KINDS[k].fields.map((f) => `<th class="r">${FIELD_SHORT[f]}</th>`).join("")}${k !== "exclusive" ? "<th class='r'>Εγγραφές (DR+CB)</th>" : ""}</tr></thead>
      <tbody><tr>${k !== "exclusive" ? `<td class="r num">${t.informed}</td>` : ""}${KINDS[k].fields.map((f) => `<td class="r num">${t[f]}</td>`).join("")}${k !== "exclusive" ? `<td class="r num">${t.total_enr}</td>` : ""}</tr></tbody></table></div>
      <div class="chips" style="margin-top:10px">${KINDS[k].metrics.map((x) => `<span class="chip" title="${h(x.formula)}">${x.label}: <strong>${fmtPct(m[x.key])}</strong></span>`).join("")}</div>
      ${w.map((x) => `<div class="note warn" style="margin-top:8px">⚠ ${h(x)}</div>`).join("")}`; }).join("")
      : `<div class="empty">Δεν υπάρχουν καταχωρίσεις στο διάστημα.</div>`}
    <p class="muted small" style="margin-top:12px">Ποσοστά από τα αθροίσματα του διαστήματος. «—» = μηδενικός παρονομαστής.</p></div>`;
  const re = () => (location.hash = `#/employee?code=${encodeURIComponent(e.code)}&tab=stats&from=${$("#cs-from").value}&to=${$("#cs-to").value}`);
  $("#cs-from").onchange = re; $("#cs-to").onchange = re;
}

async function assess(e, body) {
  if (can.assessResults()) {
    const [atts, qs, vers] = await Promise.all([S.api.attempts({ employee: e.code }), S.api.questionnaires(), S.api.versionsAll()]);
    const qT = Object.fromEntries(qs.map((q) => [q.id, q])), vN = Object.fromEntries(vers.map((v) => [v.id, v.version]));
    const state = (a) => (a.status === "in_progress" && qT[a.questionnaire_id]?.ends_at && new Date(qT[a.questionnaire_id].ends_at) < new Date() ? "expired" : a.status);
    body.innerHTML = `<div class="card">${atts.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Ερωτηματολόγιο</th><th>Κατά τη συμπλήρωση</th><th>Άνοιξε</th><th>Υποβολή</th><th>Κατάσταση</th><th class="r">Αποτέλεσμα</th></tr></thead><tbody>
      ${atts.map((a) => `<tr class="click" data-att="${h(a.id)}"><td><strong>${h(qT[a.questionnaire_id]?.title)}</strong><span class="sub">έκδοση ${vN[a.version_id]}</span></td>
        <td class="small">${h(a.store)} · ${h(a.specialty || "—")}</td><td class="small">${h(a.opened_by)}</td><td class="small">${a.submitted_at ? athens(a.submitted_at) : "—"}</td>
        <td>${attemptBadge(state(a))}</td><td class="r num">${a.score !== null && a.max_score ? `${String(a.score).replace(".", ",")} / ${String(a.max_score).replace(".", ",")}` : "—"}</td></tr>`).join("")}</tbody></table></div>`
      : `<div class="empty">Δεν υπάρχουν αξιολογήσεις.</div>`}
      <p class="muted small" style="margin-top:10px">Οι βαθμοί συγκρίνονται μόνο στην ίδια έκδοση ερωτηματολογίου. Δεν συνδυάζονται με στατιστικά πωλήσεων.</p></div>`;
    $$("[data-att]", body).forEach((tr) => (tr.onclick = () => attemptDialog(tr.dataset.att)));
  } else {
    const list = await S.api.employeeAssessments(e.code);
    body.innerHTML = `<div class="card">${list.length ? list.map((a) => `<div class="list-item"><div class="grow"><strong>${h(a.title)}</strong> <span class="muted small">έκδοση ${a.version}</span>
      <div class="muted small">${a.submitted_at ? "Υποβλήθηκε " + athens(a.submitted_at) : "Ξεκίνησε " + athens(a.started_at)} · προθεσμία ${athens(a.ends_at)}</div></div>${attemptBadge(a.state)}</div>`).join("")
      : `<div class="empty">Δεν υπάρχουν αξιολογήσεις.</div>`}
      <p class="muted small" style="margin-top:10px">Απαντήσεις και βαθμολογίες βλέπουν μόνο η Γενική Διευθύντρια και το HR.</p>
      <a class="btn primary" style="margin-top:12px" href="#/assess-run">Έναρξη αξιολόγησης</a></div>`;
  }
}
