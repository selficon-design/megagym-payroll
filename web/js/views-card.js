// Ενιαία καρτέλα εργαζομένου: ίδιος κωδικός σε όλες τις ενότητες.
// Κάθε καρτέλα φορτώνεται χωριστά και ο server επιστρέφει μόνο ό,τι επιτρέπεται στον ρόλο.
import { S, can, role, specialtyKind, P, activeStores } from "./core.js";
import { $, $$, h, dmy, money, monthLabel, badge, toast, openDialog, closeDialog } from "./util.js";
import { athensToday as todayA } from "./hr-common.js";
import { num2, settleDialog, downloadSettlementDoc } from "./views-leave.js";
import { CATEGORIES, flowOf, reqBadge, attemptBadge, athens, daysWord, demoNotice } from "./hr-common.js";
import { KINDS, FIELD_SHORT, totals, metrics, fmtPct, warnings } from "./stats-calc.js";
import { viewDeclaration } from "./views-main.js";
import { attemptDialog } from "./views-assess.js";

const view = () => $("#view");

export async function employeeCard(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Καρτέλα εργαζομένου"));
  const code = params.get("code");
  const tab = params.get("tab") || "info";
  const e = await S.api.employee(code);
  if (!e) return (view().innerHTML = `<div class="card empty">Ο εργαζόμενος δεν βρέθηκε ή δεν ανήκει στο πεδίο σας.</div>`);

  const TABS = [
    ["info", "Στοιχεία", true],
    ["payroll", "Μισθοδοσία", can.payroll()],
    ["requests", "Αιτήματα & αποφάσεις", can.requests()],
    ["leave", "Άδειες", can.leave() || can.requests()],
    ["reports", "Αναφορές & προειδοποιήσεις", can.requests()],
    ["stats", "Ημερήσια στατιστικά", P("stats.view") || can.statsReports()],
    ["assess", "Αξιολογήσεις", can.assessOpen() || can.assessResults()],
  ].filter((t) => t[2]);
  const t = TABS.some((x) => x[0] === tab) ? tab : TABS[0][0];

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Καρτέλα εργαζομένου · ${h(e.code)}</div><h1>${h(e.first)} ${h(e.last)}</h1>
    <p class="muted">${h(e.specialty || "Χωρίς ειδικότητα")} · ${h(e.store)} · ${h(e.company)} · <span class="badge ${e.status === "Ενεργός" ? "b-signed" : "b-missing"}">${h(e.status)}</span>${e.leave_date ? ` <span class="badge ${e.leave_date < todayA() ? "b-voided" : "b-pending"}">${e.leave_date < todayA() ? "Αποχώρησε" : "Αποχωρεί"} ${dmy(e.leave_date)}</span>` : ""}${e.work_week ? ` · ${e.work_week === 6 ? "Εξαήμερο" : "Πενθήμερο"}` : ""}</p></div>
    <div class="row-actions">${can.createRequests() && e.status === "Ενεργός" ? `<a class="btn" href="#/request-new?kind=manager&code=${encodeURIComponent(e.code)}">+ Αναφορά</a><a class="btn primary" href="#/request-new?kind=employee&code=${encodeURIComponent(e.code)}">+ Αίτημα</a>` : ""}</div></div>
  <div class="tabs">${TABS.map(([k, l]) => `<a href="#/employee?code=${encodeURIComponent(code)}&tab=${k}" class="${k === t ? "on" : ""}">${l}</a>`).join("")}</div>
  <div id="card-body"><div class="empty"><div class="spinner"></div></div></div>`;
  const body = $("#card-body");
  try { await ({ info, payroll, requests: reqs, leave, reports, stats, assess })[t](e, body, params); }
  catch (err) { body.innerHTML = `<div class="card note bad">${h(err.message)}</div>`; }
}

async function info(e, body) {
  const [asg, terms, life] = await Promise.all([S.api.assignments(e.code), S.api.workTerms(e.code).catch(() => []), S.api.lifecycle(e.code).catch(() => [])]);
  const ed = can.editEmployees();
  const LIFE = { hire: "Πρόσληψη", leave: "Αποχώρηση (τελευταία ημέρα)", leave_cancel: "Ακύρωση αποχώρησης", transfer: "Μόνιμη μεταφορά", work_terms: "Σύστημα εργασίας" };
  body.innerHTML = `<div class="grid g2">
    <div class="card"><div class="card-head"><h3>Βασικά στοιχεία</h3>${ed ? `<button class="btn sm" id="ci-contact">Επεξεργασία</button>` : ""}</div><dl class="kv">
      <dt>Κωδικός</dt><dd>${h(e.code)}</dd><dt>Ονοματεπώνυμο</dt><dd>${h(e.first)} ${h(e.last)}</dd>
      <dt>Email</dt><dd>${h(e.email || "—")}</dd><dt>Τηλέφωνο</dt><dd>${h(e.phone || "—")}</dd>
      <dt>Ειδικότητα</dt><dd>${h(e.specialty || "—")}</dd><dt>Κατάστημα</dt><dd>${h(e.store)}</dd><dt>Εταιρεία</dt><dd>${h(e.company)}</dd>
      <dt>Σύστημα εργασίας</dt><dd>${e.work_week ? (e.work_week === 6 ? "Εξαήμερο" : "Πενθήμερο") : `<span class="badge b-missing">Δεν έχει οριστεί</span>`}${e.weekly_hours ? ` · ${num2(e.weekly_hours)} ώρες/εβδομάδα` : ""}</dd>
      <dt>Ημ. πρόσληψης</dt><dd>${e.hire_date ? dmy(e.hire_date) : "—"}</dd><dt>Αποχώρηση</dt><dd>${e.leave_date ? `${dmy(e.leave_date)} <span class="muted small">(τελευταία ημέρα απασχόλησης)</span>` : "—"}</dd>
      <dt>Κατάσταση</dt><dd>${h(e.status)}</dd></dl>
      ${ed ? `<div class="row-actions" style="margin-top:12px"><button class="btn sm" id="ci-terms">Πενθήμερο / εξαήμερο</button><button class="btn sm" id="ci-dates">Πρόσληψη / αποχώρηση</button><button class="btn sm" id="ci-move">Μόνιμη μεταφορά</button></div>` : ""}
      ${!e.work_week || !e.hire_date ? `<p class="muted small" style="margin-top:12px">${ed ? "Συμπληρώστε σύστημα εργασίας και ημερομηνία πρόσληψης: χρειάζονται για τις ημέρες χρέωσης και την αναλογία αδειών." : "Λείπουν στοιχεία· τα συμπληρώνουν ΓΔ, HR ή λογιστήριο."}</p>` : ""}
    </div>
    <div class="card"><h3>Ιστορικό θέσης</h3><p class="muted small">Ο κωδικός μένει ίδιος· κάθε παλιά εγγραφή κρατά το κατάστημα και την ειδικότητα της περιόδου της.</p>
      <div class="table-wrap" style="margin-top:10px"><table><thead><tr><th>Από</th><th>Έως</th><th>Κατάστημα</th><th>Ειδικότητα</th></tr></thead><tbody>
      ${asg.map((a) => `<tr><td class="small">${athens(a.valid_from, false)}</td><td class="small">${a.valid_to ? athens(a.valid_to, false) : "σήμερα"}</td><td>${h(a.store)}</td><td>${h(a.specialty || "—")}</td></tr>`).join("")}
      </tbody></table></div>
      <h4 style="margin-top:14px">Σύστημα εργασίας (με ημερομηνία ισχύος)</h4>
      ${terms.length ? `<div class="table-wrap"><table><thead><tr><th>Ισχύς από</th><th>Σύστημα</th><th class="r">Ώρες/εβδ.</th><th>Σημείωση</th></tr></thead><tbody>${terms.map((t) => `<tr><td>${dmy(t.valid_from)}</td><td>${t.work_week === 6 ? "Εξαήμερο" : "Πενθήμερο"}</td><td class="r num">${t.weekly_hours ? num2(t.weekly_hours) : "—"}</td><td class="small">${h(t.note || "")}<span class="sub">${h(t.set_by)}</span></td></tr>`).join("")}</tbody></table></div>` : `<p class="muted small">Καμία καταχώριση.</p>`}
    </div></div>
    ${life.length ? `<div class="card" style="margin-top:16px"><h3>Κύκλος ζωής</h3>${life.map((l) => `<div class="list-item"><div class="grow small"><strong>${LIFE[l.kind] || l.kind}</strong>${l.effective_date ? ` · ισχύς ${dmy(l.effective_date)}` : ""}${l.new_value?.store ? ` · ${h(l.old_value?.store || "")} → ${h(l.new_value.store)}` : ""}${l.note ? ` — ${h(l.note)}` : ""}<div class="muted">${h(l.actor)} · ${athens(l.at)}</div></div></div>`).join("")}</div>` : ""}`;
  const reload = () => window.dispatchEvent(new Event("mg:rerender"));
  const dlg = (title, inner, run) => openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(e.first)} ${h(e.last)} · ${h(e.code)}</div><h2>${title}</h2></div><button class="icon-btn" data-close>✕</button></div>${inner}
      <p id="cd-m" class="form-msg"></p><div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="cd-ok">Αποθήκευση</button></div>`,
    { onOpen() { $("#cd-ok").onclick = async () => { try { await run(); closeDialog(); toast("Αποθηκεύτηκε."); reload(); } catch (err) { $("#cd-m").textContent = err.message; } }; } });
  $("#ci-contact") && ($("#ci-contact").onclick = () => dlg("Στοιχεία επικοινωνίας", `<div class="grid g2"><div><label>Email</label><input id="cd-email" type="email" value="${h(e.email || "")}"></div><div><label>Τηλέφωνο</label><input id="cd-phone" value="${h(e.phone || "")}"></div></div>`,
    () => S.api.saveEmployee({ code: e.code, email: $("#cd-email").value.trim().toLowerCase() || null, phone: $("#cd-phone").value.trim() || null }, false)));
  $("#ci-terms") && ($("#ci-terms").onclick = () => dlg("Πενθήμερο / εξαήμερο", `<p class="muted small">Ορίζεται ανά εργαζόμενο. Κάθε αλλαγή κρατά ημερομηνία ισχύος και ιστορικό· δεν αντικαθιστά σιωπηρά παλιές εγγραφές.</p>
      <div class="grid g3"><div><label>Σύστημα</label><select id="cd-ww"><option value="5" ${e.work_week === 5 ? "selected" : ""}>Πενθήμερο</option><option value="6" ${e.work_week === 6 ? "selected" : ""}>Εξαήμερο</option></select></div>
      <div><label>Συμβατικές ώρες / εβδομάδα</label><input id="cd-wh" inputmode="decimal" value="${e.weekly_hours ? String(e.weekly_hours).replace(".", ",") : ""}"></div><div><label>Ισχύει από</label><input type="date" id="cd-from" value="${todayA()}"></div></div>
      <label>Σημείωση</label><input id="cd-note" maxlength="300">`,
    () => S.api.empSetWorkTerms(e.code, Number($("#cd-ww").value), $("#cd-wh").value ? Number($("#cd-wh").value.replace(",", ".")) : null, $("#cd-from").value, $("#cd-note").value)));
  $("#ci-dates") && ($("#ci-dates").onclick = () => dlg("Πρόσληψη / αποχώρηση", `<p class="muted small">Η ημερομηνία αποχώρησης είναι η <strong>τελευταία ημέρα απασχόλησης</strong>. Μετά από αυτήν ο εργαζόμενος δεν μετρά στη στελέχωση· οι προγραμματισμένες βάρδιες επισημαίνονται για κάλυψη. Η καρτέλα και όλο το ιστορικό διατηρούνται.</p>
      <div class="grid g2"><div><label>Πρόσληψη</label><input type="date" id="cd-hire" value="${h(e.hire_date || "")}"></div><div><label>Αποχώρηση (κενό = όχι)</label><input type="date" id="cd-leave" value="${h(e.leave_date || "")}"></div></div>
      <label>Σημείωση</label><input id="cd-note" maxlength="300">`,
    () => S.api.empSetDates(e.code, $("#cd-hire").value, $("#cd-leave").value, $("#cd-note").value)));
  $("#ci-move") && ($("#ci-move").onclick = () => dlg("Μόνιμη μεταφορά καταστήματος", `<p class="muted small">Ίδιος μοναδικός κωδικός και ιστορικό. Οι παλιές εγγραφές (δηλώσεις, αιτήματα, στατιστικά) κρατούν το κατάστημα στο οποίο αφορούσαν. Το σταθερό πρόγραμμα του παλιού καταστήματος λήγει την προηγούμενη ημέρα.</p>
      <div class="grid g2"><div><label>Νέο κατάστημα</label><select id="cd-store">${activeStores().filter((x) => x !== e.store).map((x) => `<option>${h(x)}</option>`).join("")}</select></div><div><label>Ισχύει από</label><input type="date" id="cd-eff" value="${todayA()}" max="${todayA()}"></div></div>
      <label>Σημείωση</label><input id="cd-note" maxlength="300">`,
    () => S.api.empTransfer(e.code, $("#cd-store").value, $("#cd-eff").value, $("#cd-note").value)));
}

async function payroll(e, body) {
  const ds = await S.api.declarations({});
  const mine = ds.filter((d) => d.employee_code === e.code);
  body.innerHTML = `<div class="card">${mine.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Μήνας</th><th>Κατάστημα</th><th class="r">Ποσό</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
    ${mine.map((d) => `<tr><td>${h(monthLabel(d.month))}</td><td data-l="Κατάστημα">${h(d.store)}</td><td class="r num">${money(d.amount)}</td><td>${badge(d.status)}${d.signed_at ? `<span class="sub">${athens(d.signed_at)}</span>` : ""}</td>
      <td style="text-align:right">${d.status !== "pending" ? `<button class="btn sm" data-view="${h(d.id)}">Προβολή${can.pdf() ? " / PDF" : ""}</button>` : ""}</td></tr>`).join("")}</tbody></table></div>`
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
async function leave(e, body, params) {
  const asOf = params.get("asof") || todayA();
  const [{ visible, cur }, C] = await Promise.all([can.requests() ? loadReqs(e) : { visible: [], cur: {} }, can.leave() ? S.api.leaveCard(e.code, asOf).catch((err) => ({ error: err.message })) : null]);
  const rows = visible.filter((x) => ["leave", "leave_change"].includes(x.category));
  const B = C?.balance, SK = C?.sick;
  const kpi = (label, v, hint = "", cls = "") => `<div class="card kpi ${cls}"><div class="label">${label}</div><div class="value num">${v}</div>${hint ? `<div class="hint">${hint}</div>` : ""}</div>`;
  body.innerHTML = `${C && !C.error ? `
    <div class="card"><div class="card-head"><h3>Κανονική άδεια ${B.year}</h3>
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Έως ημερομηνία <input type="date" id="lv-asof" value="${asOf}" style="width:auto"></label></div>
      ${B.base_missing ? `<div class="note warn">Δεν έχει οριστεί ετήσια βάση άδειας. ${can.leaveAdjust() ? "Ορίστε την παρακάτω (υπάρχει πρόταση από πρόσληψη και σύστημα εργασίας)." : "Την ορίζουν ΓΔ, HR ή λογιστήριο."}</div>` : ""}
      <div class="grid g3" style="margin-top:10px">
        ${kpi("Ετήσιες ημέρες άδειας", num2(B.annual_days), "βάση σε ισχύ")}
        ${kpi("Αναλογία έως " + dmy(B.as_of), num2(B.accrued), "μηνιαία αναλογία · μέρος μήνα από πρόσληψη")}
        ${kpi("Ληφθείσες", num2(B.taken))}
        ${kpi("Εγκεκριμένες μελλοντικές", num2(B.future_approved))}
        ${kpi("Υπόλοιπο βάσει αναλογίας", num2(B.balance), Number(B.adjustments) ? `περιλαμβάνει διορθώσεις ${num2(B.adjustments)}` : "", Number(B.balance) < 0 ? "bad" : "ok")}
        ${kpi("Υπόλοιπο " + B.prev_year, num2(B.prev_balance), B.prev_state === "usable" ? `διαθέσιμο έως ${dmy(B.prev_deadline)}` : B.prev_state === "to_settle" ? `<span class="badge b-pending">Προς εκκαθάριση από το λογιστήριο</span>` : "", B.prev_state === "to_settle" ? "warn" : "")}
      </div>
      <p class="muted small" style="margin-top:8px">Η αναλογία είναι εσωτερικός δείκτης προγραμματισμού (δύο δεκαδικά, χωρίς μηνιαία στρογγυλοποίηση) και δεν αποτελεί από μόνη της νομική κρίση ή λόγο απόρριψης. Οι ημέρες χρέωσης προκύπτουν από το πρόγραμμα/σύστημα εργασίας του εργαζομένου, χωρίς αργίες.</p>
      <div class="row-actions" style="margin-top:10px">${can.leaveAdjust() ? `<button class="btn sm" id="lv-adj">Διόρθωση υπολοίπου</button><button class="btn sm" id="lv-base">Ετήσια βάση</button>` : ""}${can.leaveSettle() && B.prev_state === "to_settle" ? `<button class="btn sm primary" id="lv-pay">Πληρωμή εκκαθάρισης ${B.prev_year}</button>` : ""}</div>
    </div>
    ${SK?.known ? `<div class="card" style="margin-top:16px"><h3>Αναρρωτικές — κάλυψη αποδοχών (χωριστά από την απουσία)</h3>
      <p class="small" style="margin-top:6px">Εργασιακό έτος ${dmy(SK.work_year_start)} – ${dmy(SK.work_year_end)} · ημέρες αναρρωτικής: <strong>${SK.sick_days}</strong> · με κάλυψη: <strong>${SK.covered}</strong>${SK.cover_limit ? ` / όριο ${SK.cover_limit} (${h(SK.cover_limit_rule)})` : ""}${SK.ten_day_condition_unmet_days ? ` · ${SK.ten_day_condition_unmet_days} ημέρες πριν από 10 ημέρες παροχής εργασίας` : ""}</p>
      ${SK.message ? `<div class="note warn" style="margin-top:8px">${h(SK.message)}</div>` : ""}
      <p class="muted small" style="margin-top:6px">Η κάλυψη αποδοχών δεν είναι όριο απουσίας· η καταχώριση αναρρωτικής δεν μπλοκάρεται και δεν αφαιρείται από την κανονική άδεια.</p></div>` : ""}
    <div class="grid g2" style="margin-top:16px">
      <div class="card"><h3>Ετήσιες βάσεις</h3>${C.entitlements.length ? C.entitlements.map((x) => `<div class="list-item small ${x.superseded_at ? "muted" : ""}"><div class="grow">Από ${dmy(x.valid_from)}: <strong>${num2(x.annual_days)}</strong> ημέρες${x.note ? ` — ${h(x.note)}` : ""}<div class="muted">${h(x.set_by)} · ${athens(x.set_at)}${x.superseded_at ? ` · αντικαταστάθηκε ${athens(x.superseded_at)}` : ""}</div></div></div>`).join("") : `<p class="muted small">Καμία.</p>`}</div>
      <div class="card"><h3>Διορθώσεις & εκκαθαρίσεις</h3>
        ${C.adjustments.map((x) => `<div class="list-item small"><div class="grow">Διόρθωση ${x.leave_year}: ${num2(x.prev_value)} → <strong>${num2(x.new_value)}</strong> — ${h(x.reason)}<div class="muted">${h(x.created_by)} · ${athens(x.created_at)}</div></div></div>`).join("")}
        ${C.settlements.map((x) => `<div class="list-item small ${x.voided_at ? "muted" : ""}"><div class="grow">Εκκαθάριση ${x.leave_year}: <strong>${num2(x.days)}</strong> ημέρες · ${money(x.amount)} · πληρωμή ${dmy(x.paid_on)}${x.voided_at ? ` · ακυρώθηκε: ${h(x.void_reason)}` : ""}<div class="muted">${h(x.created_by)} · ${athens(x.created_at)}</div></div>${x.has_doc ? `<button class="btn sm" data-doc="${x.id}">Παραστατικό</button>` : ""}</div>`).join("")}
        ${!C.adjustments.length && !C.settlements.length ? `<p class="muted small">Καμία.</p>` : ""}</div>
    </div>
    <div class="card" style="margin-top:16px"><h3>Ημέρες άδειας / απουσίας</h3>
      ${C.days.length ? `<div class="table-wrap" style="max-height:300px"><table><thead><tr><th>Ημέρα</th><th>Είδος</th><th>Αίτημα</th><th class="r">Χρέωση</th><th>Έτος χρέωσης</th><th>Κατάσταση</th></tr></thead><tbody>
        ${C.days.map((d) => `<tr class="${d.status !== "active" ? "muted" : ""}"><td>${dmy(d.day)}</td><td class="small">${h(d.label || d.leave_type)}</td><td class="small"><a href="#/request?id=${h(d.request_id)}">${h(d.ref)}</a></td><td class="r num">${Number(d.charge) ? num2(d.charge) : "—"}</td>
          <td class="small">${(d.years || []).map((y) => `${y.year}: ${num2(y.amount)}`).join(" · ") || "—"}</td><td class="small">${{ active: "Ενεργή", cancelled: "Ακυρώθηκε", replaced: "Αντικαταστάθηκε" }[d.status]}${d.end_reason ? `<span class="sub">${h(d.end_reason)}</span>` : ""}</td></tr>`).join("")}
      </tbody></table></div>` : `<p class="muted small">Δεν υπάρχουν ημέρες.</p>`}</div>` : C?.error ? `<div class="card note bad">${h(C.error)}</div>` : ""}
    ${can.requests() ? `<div class="card" style="margin-top:16px"><div class="card-head"><h3>Αιτήσεις άδειας</h3></div>${reqTable(rows, cur, (x) => `<span class="sub">${h(x.leave_type_label || "")} · ${dmy(x.start_date)} – ${dmy(x.end_date)}</span>`)}</div>` : ""}`;
  bindRows(body);
  const re = (d) => (location.hash = `#/employee?code=${encodeURIComponent(e.code)}&tab=leave&asof=${d || asOf}`);
  $("#lv-asof") && ($("#lv-asof").onchange = (ev) => re(ev.target.value));
  $$("[data-doc]", body).forEach((b) => (b.onclick = () => downloadSettlementDoc(Number(b.dataset.doc))));
  const reload = () => window.dispatchEvent(new Event("mg:rerender"));
  $("#lv-pay") && ($("#lv-pay").onclick = () => settleDialog({ employee_code: e.code, employee_name: `${e.first} ${e.last}`, leave_year: B.prev_year, outstanding: B.prev_balance }, reload));
  $("#lv-adj") && ($("#lv-adj").onclick = () => openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(e.first)} ${h(e.last)}</div><h2>Διόρθωση υπολοίπου</h2></div><button class="icon-btn" data-close>✕</button></div>
      <p class="muted small">Καταγράφονται αιτιολογία, προηγούμενη και νέα τιμή, χρήστης και χρόνος. Η διόρθωση προστίθεται στο ιστορικό κινήσεων — δεν αντικαθιστά παλιές εγγραφές.</p>
      <div class="grid g3"><div><label>Έτος άδειας</label><select id="ad-y"><option>${B.year}</option><option>${B.prev_year}</option><option>${B.prev_year - 1}</option></select></div>
        <div><label>Νέο υπόλοιπο</label><input id="ad-v" inputmode="decimal"></div><div><label>Ημερομηνία αναφοράς</label><input type="date" id="ad-d" value="${asOf}"></div></div>
      <p class="muted small" id="ad-cur">Τρέχον υπόλοιπο ${B.year} (μετά τις εγκεκριμένες): ${num2(B.balance)} · ${B.prev_year}: ${num2(B.prev_balance)}</p>
      <label>Αιτιολογία</label><textarea id="ad-r" rows="2" maxlength="1000"></textarea><p id="ad-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="ad-ok">Καταχώριση διόρθωσης</button></div>`, {
    onOpen() { $("#ad-ok").onclick = async () => { try { const r = await S.api.leaveAdjust(e.code, Number($("#ad-y").value), Number($("#ad-v").value.replace(",", ".")), $("#ad-d").value, $("#ad-r").value.trim()); closeDialog(); toast(`Διόρθωση: ${num2(r.prev)} → ${num2(r.new)}`); reload(); } catch (err) { $("#ad-m").textContent = err.message; } }; } }));
  $("#lv-base") && ($("#lv-base").onclick = async () => {
    const sug = await S.api.leaveSuggest(e.code).catch(() => ({ rows: [] }));
    openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(e.first)} ${h(e.last)}</div><h2>Ετήσια βάση κανονικής άδειας</h2></div><button class="icon-btn" data-close>✕</button></div>
      ${sug.rows?.length ? `<p class="muted small">Πρόταση από πρόσληψη & σύστημα εργασίας — ${h(sug.rule || "")}:</p>${sug.rows.map((x) => `<div class="list-item small"><div class="grow">Από ${dmy(x.valid_from)}: <strong>${x.annual_days}</strong> ημέρες (${x.work_week === 6 ? "εξαήμερο" : "πενθήμερο"}, ${x.service_years} έτη)</div>${x.exists ? `<span class="badge b-signed">Υπάρχει</span>` : `<button class="btn sm" data-sug="${x.valid_from}|${x.annual_days}">Αποθήκευση</button>`}</div>`).join("")}` : `<p class="muted small">${h(sug.note || "Δεν υπάρχει πρόταση.")}</p>`}
      <h4 style="margin-top:12px">Χειροκίνητη καταχώριση</h4>
      <div class="grid g3"><div><label>Ετήσιες ημέρες</label><input id="eb-d" inputmode="decimal"></div><div><label>Ισχύει από</label><input type="date" id="eb-f"></div><div><label class="check" style="margin-top:28px"><input type="checkbox" id="eb-r"> Διόρθωση υπάρχουσας</label></div></div>
      <label>Σημείωση / αιτιολογία</label><input id="eb-n" maxlength="300"><p id="eb-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Κλείσιμο</button><button class="btn primary" id="eb-ok">Αποθήκευση</button></div>`, {
      onOpen() {
        $$("[data-sug]").forEach((b) => (b.onclick = async () => { const [f, d] = b.dataset.sug.split("|"); try { await S.api.leaveSetBase(e.code, Number(d), f, "Από πρόταση εφαρμογής"); closeDialog(); toast("Αποθηκεύτηκε."); reload(); } catch (err) { $("#eb-m").textContent = err.message; } }));
        $("#eb-ok").onclick = async () => { try { await S.api.leaveSetBase(e.code, Number($("#eb-d").value.replace(",", ".")), $("#eb-f").value, $("#eb-n").value, $("#eb-r").checked); closeDialog(); toast("Αποθηκεύτηκε."); reload(); } catch (err) { $("#eb-m").textContent = err.message; } };
      },
    });
  });
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
  if (!can.assessFull() && can.assessResults()) {
    const rows = await S.api.assessResults(null, e.code);
    body.innerHTML = `<div class="card">${rows.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Ερωτηματολόγιο</th><th>Κατά τη συμπλήρωση</th><th>Υποβολή</th><th>Κατάσταση</th><th class="r">Αποτέλεσμα</th></tr></thead><tbody>
      ${rows.map((a) => `<tr class="click" data-att="${h(a.attempt_id)}"><td><strong>${h(a.title)}</strong>${a.kind === "exit_interview" ? ` <span class="badge b-info">Exit Interview</span>` : ""}<span class="sub">έκδοση ${a.version}</span></td>
        <td class="small">${h(a.store)} · ${h(a.specialty || "—")}</td><td class="small">${a.submitted_at ? athens(a.submitted_at) : "—"}</td><td>${attemptBadge(a.state)}</td>
        <td class="r num">${a.max_score ? `${String(a.score ?? "—").replace(".", ",")} / ${String(a.max_score).replace(".", ",")}` : "—"}</td></tr>`).join("")}</tbody></table></div>` : `<div class="empty">Δεν υπάρχουν αξιολογήσεις.</div>`}
      ${can.assessOpen() ? `<a class="btn primary" style="margin-top:12px" href="#/assess-run">Έναρξη αξιολόγησης</a>` : ""}</div>`;
    $$("[data-att]", body).forEach((tr) => (tr.onclick = () => attemptDialog(tr.dataset.att)));
    return;
  }
  if (can.assessFull()) {
    const [atts, qs, vers, asg] = await Promise.all([S.api.attempts({ employee: e.code }), S.api.questionnaires(), S.api.versionsAll(), S.api.linkAssignments({ employee: e.code })]);
    const qT = Object.fromEntries(qs.map((q) => [q.id, q])), vN = Object.fromEntries(vers.map((v) => [v.id, v.version]));
    const state = (a) => { const end = a.due_at || qT[a.questionnaire_id]?.ends_at; return a.status === "in_progress" && end && new Date(end) < new Date() ? "expired" : a.status; };
    // Προσωπικοί σύνδεσμοι που δεν έχουν ανοιχτεί ακόμη
    const opened = new Set(atts.map((a) => a.assignment_id).filter(Boolean));
    const waiting = asg.filter((g) => g.status === "active" && !g.completed_at && !opened.has(g.id));
    body.innerHTML = `<div class="card">${atts.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Ερωτηματολόγιο</th><th>Κατά τη συμπλήρωση</th><th>Άνοιξε</th><th>Υποβολή</th><th>Κατάσταση</th><th class="r">Αποτέλεσμα</th></tr></thead><tbody>
      ${atts.map((a) => `<tr class="click" data-att="${h(a.id)}"><td><strong>${h(qT[a.questionnaire_id]?.title)}</strong>${qT[a.questionnaire_id]?.kind === "exit_interview" ? ` <span class="badge b-info">Exit Interview</span>` : ""}<span class="sub">έκδοση ${vN[a.version_id]}</span></td>
        <td class="small">${h(a.store)} · ${h(a.specialty || "—")}</td><td class="small">${a.opened_role === "link" ? "Προσωπικός σύνδεσμος" : h(a.opened_by)}</td><td class="small">${a.submitted_at ? athens(a.submitted_at) : "—"}</td>
        <td>${attemptBadge(state(a))}</td><td class="r num">${a.score !== null && a.max_score ? `${String(a.score).replace(".", ",")} / ${String(a.max_score).replace(".", ",")}` : "—"}</td></tr>`).join("")}</tbody></table></div>`
      : waiting.length ? "" : `<div class="empty">Δεν υπάρχουν αξιολογήσεις.</div>`}
      ${waiting.length ? `<h4 style="margin-top:14px">Ανατεθειμένες μέσω προσωπικού συνδέσμου — δεν έχουν ανοιχτεί</h4>${waiting.map((g) => `<div class="list-item small"><div class="grow"><strong>${h(qT[g.questionnaire_id]?.title)}</strong> <span class="muted">έκδοση ${vN[g.version_id]}</span><div class="muted">Διαθέσιμη ${athens(g.starts_at)} → ${athens(g.ends_at)}</div></div>${attemptBadge(new Date(g.ends_at) < new Date() ? "expired" : "not_started")}</div>`).join("")}` : ""}
      <p class="muted small" style="margin-top:10px">Οι βαθμοί συγκρίνονται μόνο στην ίδια έκδοση ερωτηματολογίου. Δεν συνδυάζονται με στατιστικά πωλήσεων.</p></div>`;
    $$("[data-att]", body).forEach((tr) => (tr.onclick = () => attemptDialog(tr.dataset.att)));
  } else {
    const list = await S.api.employeeAssessments(e.code);
    body.innerHTML = `<div class="card">${list.length ? list.map((a) => `<div class="list-item"><div class="grow"><strong>${h(a.title)}</strong> <span class="muted small">έκδοση ${a.version}</span>
      <div class="muted small">${a.submitted_at ? "Υποβλήθηκε " + athens(a.submitted_at) : a.started_at ? "Ξεκίνησε " + athens(a.started_at) : "Δεν έχει ανοιχτεί"} · προθεσμία ${athens(a.ends_at)}</div></div>${attemptBadge(a.state)}</div>`).join("")
      : `<div class="empty">Δεν υπάρχουν αξιολογήσεις.</div>`}
      <p class="muted small" style="margin-top:10px">Απαντήσεις και βαθμολογίες βλέπουν όσοι έχουν το αντίστοιχο δικαίωμα.</p>
      ${can.assessOpen() ? `<a class="btn primary" style="margin-top:12px" href="#/assess-run">Έναρξη αξιολόγησης</a>` : ""}</div>`;
  }
}
