// Άδειες: συγκεντρωτικό ημερολόγιο (έτος/μήνας), «Προς εκκαθάριση από το λογιστήριο», αργίες.
// Απαντήσεις (αδιάβαστες ενημερώσεις ανά χρήστη) και εργασίες HR/λογιστηρίου.
// Όλοι οι υπολογισμοί γίνονται στον server· εδώ μόνο εμφάνιση.
import { S, can, role, visibleStores, activeSpecialties } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, confirmBox, dmy, money, saveBlob } from "./util.js";
import { athens, athensToday, fileToPayload, base64ToBlob, CATEGORIES, demoNotice } from "./hr-common.js";

const view = () => $("#view");
const MONTHS = ["Ιανουάριος", "Φεβρουάριος", "Μάρτιος", "Απρίλιος", "Μάιος", "Ιούνιος", "Ιούλιος", "Αύγουστος", "Σεπτέμβριος", "Οκτώβριος", "Νοέμβριος", "Δεκέμβριος"];
const DOW = ["Κυ", "Δε", "Τρ", "Τε", "Πε", "Πα", "Σα"];
const pad = (n) => String(n).padStart(2, "0");
const iso = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
const daysIn = (y, m) => new Date(y, m, 0).getDate();
export const num2 = (v) => (v === null || v === undefined || v === "" ? "—" : Number(v).toLocaleString("el-GR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));

// Σταθερό χρώμα ανά εργαζόμενο (από τον κωδικό του)
export function empColor(code) {
  let x = 0; for (const c of String(code)) x = (x * 31 + c.charCodeAt(0)) >>> 0;
  return `hsl(${x % 360} 62% 42%)`;
}
const STATUS_GR = { approved: "Εγκρίθηκε", pending: "Σε αναμονή", cancelled: "Ακυρώθηκε", rejected: "Απορρίφθηκε" };
const STATUS_MARK = { approved: "✓", pending: "⏳", cancelled: "✕", rejected: "✕" };

// ═══════════════════════ Άδειες ═══════════════════════
export async function leaves(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Άδειες"));
  const tabs = [["cal", "Ημερολόγιο αδειών", true], ["settle", "Προς εκκαθάριση", can.leaveSettle() || can.leaveAdjust()], ["hol", "Αργίες", can.settings()]].filter((t) => t[2]);
  const tab = tabs.some((t) => t[0] === params.get("tab")) ? params.get("tab") : "cal";
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Προσωπικό</div><h1>Άδειες</h1>
    <p class="muted">${role() === "manager" ? `Κατάστημα ${h(S.me.store)}. ` : ""}Από τα ίδια δεδομένα των αιτημάτων — καμία δεύτερη καταχώριση.</p></div></div>
  <div class="tabs">${tabs.map(([k, l]) => `<a href="#/leaves?tab=${k}" class="${k === tab ? "on" : ""}">${l}</a>`).join("")}</div>
  <div id="lv-body"><div class="empty"><div class="spinner"></div></div></div>`;
  const body = $("#lv-body");
  if (tab === "settle") return settleTab(body);
  if (tab === "hol") return holidaysTab(body);
  return calendarTab(body);
}

async function calendarTab(body) {
  const today = athensToday();
  const F = (S.filters.lvcal ??= { mode: "month", y: Number(today.slice(0, 4)), m: Number(today.slice(5, 7)), store: "", spec: "", closed: false });
  const from = F.mode === "year" ? iso(F.y, 1, 1) : iso(F.y, F.m, 1);
  const to = F.mode === "year" ? iso(F.y, 12, 31) : iso(F.y, F.m, daysIn(F.y, F.m));
  const [rows, hol] = await Promise.all([S.api.leaveCalendar(from, to, F.store, F.spec, F.closed), S.api.holidays().catch(() => [])]);
  const H = Object.fromEntries(hol.map((x) => [x.day, x.label]));
  const byDay = {}; for (const r of rows) (byDay[r.day] ??= []).push(r);
  const emps = [...new Map(rows.map((r) => [r.employee_code, r.employee_name])).entries()];
  const chip = (r) => `<a class="lv-chip ${r.status}" href="#/request?id=${h(r.request_id)}" style="--c:${empColor(r.employee_code)}" title="${h(r.employee_name)} · ${h(r.label || "")} · ${STATUS_GR[r.status]} · ${h(r.ref)}">
      <span class="mk" aria-hidden="true">${STATUS_MARK[r.status]}</span>${h(r.employee_name)}<span class="sr">${STATUS_GR[r.status]}</span></a>`;
  let grid;
  if (F.mode === "month") {
    const n = daysIn(F.y, F.m);
    const cols = Array.from({ length: n }, (_, i) => iso(F.y, F.m, i + 1));
    grid = `<div class="lv-month" style="--n:${n}">
      ${cols.map((d) => { const dw = new Date(d + "T12:00:00").getDay(); return `<div class="lv-col ${dw === 0 || dw === 6 ? "we" : ""} ${H[d] ? "hol" : ""} ${d === today ? "today" : ""}">
        <div class="lv-head"><span>${DOW[dw]}</span><strong>${Number(d.slice(8))}</strong>${H[d] ? `<span class="hl" title="${h(H[d])}">αργία</span>` : ""}</div>
        <div class="lv-cell">${(byDay[d] || []).map(chip).join("")}</div></div>`; }).join("")}</div>`;
  } else {
    grid = `<div class="table-wrap"><table class="lv-year"><thead><tr><th>Μήνας</th>${Array.from({ length: 31 }, (_, i) => `<th>${i + 1}</th>`).join("")}</tr></thead><tbody>
      ${MONTHS.map((mn, mi) => `<tr><th><a href="javascript:void 0" data-month="${mi + 1}">${mn}</a></th>${Array.from({ length: 31 }, (_, i) => {
        if (i + 1 > daysIn(F.y, mi + 1)) return `<td class="na"></td>`;
        const d = iso(F.y, mi + 1, i + 1), list = byDay[d] || [];
        const ap = list.filter((r) => r.status === "approved"), pe = list.filter((r) => r.status === "pending");
        const dw = new Date(d + "T12:00:00").getDay();
        return `<td class="${dw === 0 || dw === 6 ? "we" : ""} ${H[d] ? "hol" : ""}" title="${h(list.map((r) => `${r.employee_name} (${STATUS_GR[r.status]})`).join("\n"))}">${ap.length ? `<span class="yd ap" style="--c:${empColor(ap[0].employee_code)}">${ap.length}</span>` : ""}${pe.length ? `<span class="yd pe">${pe.length}</span>` : ""}</td>`;
      }).join("")}</tr>`).join("")}
      </tbody></table></div>`;
  }
  body.innerHTML = `<div class="card">
    <div class="toolbar">
      <div class="seg" role="radiogroup"><button type="button" class="${F.mode === "month" ? "on" : ""}" data-mode="month">Μήνας</button><button type="button" class="${F.mode === "year" ? "on" : ""}" data-mode="year">Έτος</button></div>
      <button class="btn sm" id="lc-prev" aria-label="Προηγούμενο">◀</button>
      <strong>${F.mode === "month" ? `${MONTHS[F.m - 1]} ${F.y}` : F.y}</strong>
      <button class="btn sm" id="lc-next" aria-label="Επόμενο">▶</button>
      ${role() === "manager" ? "" : `<select id="lc-store"><option value="">Όλα τα καταστήματα</option>${visibleStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>`}
      <select id="lc-spec"><option value="">Όλα τα τμήματα</option>${activeSpecialties().map((s) => `<option ${s === F.spec ? "selected" : ""}>${h(s)}</option>`).join("")}</select>
      <label class="check" style="margin:0"><input type="checkbox" id="lc-closed" ${F.closed ? "checked" : ""}> Απορρίψεις & ακυρώσεις</label>
    </div>
    <div class="legend" style="margin-bottom:10px"><span><span class="lv-chip approved" style="--c:#2a7">✓ Εγκρίθηκε</span></span><span><span class="lv-chip pending" style="--c:#2a7">⏳ Σε αναμονή</span></span>
      <span class="muted small">Οι εκκρεμείς άδειες φαίνονται για προγραμματισμό αλλά δεν αφαιρούν τον εργαζόμενο από την κάλυψη. Κάθε εργαζόμενος έχει σταθερό χρώμα.</span></div>
    ${grid}
    ${emps.length ? `<p class="muted small" style="margin-top:10px">${emps.length} εργαζόμενοι με άδεια στο διάστημα · ${rows.filter((r) => r.status === "approved").length} εγκεκριμένες ημέρες · ${rows.filter((r) => r.status === "pending").length} ημέρες σε αναμονή</p>` : `<p class="muted" style="margin-top:10px">Καμία άδεια στο διάστημα.</p>`}
  </div>`;
  const re = () => calendarTab(body);
  $$("[data-mode]", body).forEach((b) => (b.onclick = () => { F.mode = b.dataset.mode; re(); }));
  $("#lc-prev").onclick = () => { if (F.mode === "year") F.y--; else if (--F.m < 1) { F.m = 12; F.y--; } re(); };
  $("#lc-next").onclick = () => { if (F.mode === "year") F.y++; else if (++F.m > 12) { F.m = 1; F.y++; } re(); };
  $("#lc-store") && ($("#lc-store").onchange = (e) => { F.store = e.target.value; re(); });
  $("#lc-spec").onchange = (e) => { F.spec = e.target.value; re(); };
  $("#lc-closed").onchange = (e) => { F.closed = e.target.checked; re(); };
  $$("[data-month]", body).forEach((a) => (a.onclick = () => { F.mode = "month"; F.m = Number(a.dataset.month); re(); }));
}

async function settleTab(body) {
  const t = athensToday(); const y = Number(t.slice(0, 4));
  const F = (S.filters.lvset ??= { year: t.slice(5) > "03-31" ? y - 1 : y - 2 });
  const rows = await S.api.leaveToSettle(F.year);
  body.innerHTML = `<div class="card">
    <div class="toolbar"><label class="small muted" style="margin:0">Έτος άδειας</label>
      <select id="st-y">${[y - 1, y - 2, y - 3, y - 4].map((x) => `<option ${x === F.year ? "selected" : ""}>${x}</option>`).join("")}</select>
      <span class="muted small">Μη ληφθείσες ημέρες του ${F.year}, μαζί με τα δεκαδικά, μετά την προθεσμία της 31/03/${F.year + 1}.</span></div>
    <div class="note" style="margin-bottom:12px">Οι ημέρες ΔΕΝ χαρακτηρίζονται αυτόματα πληρωμένες. Ο υπολογισμός αποδοχών και τυχόν προσαύξησης ελέγχεται από το λογιστήριο· η εφαρμογή καταγράφει ημέρες, ποσό, ημερομηνία, χρήστη και παραστατικό, και αποτρέπει διπλή πληρωμή.</div>
    ${rows.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα</th><th class="r">Προς εκκαθάριση</th><th class="r">Έχουν πληρωθεί</th><th></th></tr></thead><tbody>
      ${rows.map((r) => `<tr><td><a href="#/employee?code=${encodeURIComponent(r.employee_code)}&tab=leave"><strong>${h(r.employee_name)}</strong></a><span class="sub">${h(r.employee_code)}</span></td>
        <td data-l="Κατάστημα">${h(r.store)}</td><td class="r num" data-l="Προς εκκαθάριση"><span class="badge b-pending">Προς εκκαθάριση από το λογιστήριο</span> <strong>${num2(r.outstanding)}</strong></td>
        <td class="r num">${num2(r.settled)}</td><td class="acts" style="text-align:right">${can.leaveSettle() ? `<button class="btn sm primary" data-pay="${h(r.employee_code)}">Πληρωμή</button>` : ""}</td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty">Δεν υπάρχουν υπόλοιπα προς εκκαθάριση για το ${F.year}${t.slice(5) <= "03-31" && F.year === y - 1 ? " (η προθεσμία λήψης δεν έχει λήξει ακόμη)" : ""}.</div>`}
  </div>`;
  $("#st-y").onchange = (e) => { F.year = Number(e.target.value); settleTab(body); };
  $$("[data-pay]", body).forEach((b) => (b.onclick = () => settleDialog(rows.find((r) => r.employee_code === b.dataset.pay), () => settleTab(body))));
}

export function settleDialog(r, reload) {
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">Εκκαθάριση άδειας ${r.leave_year}</div><h2>${h(r.employee_name)}</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Υπόλοιπο προς εκκαθάριση: <strong>${num2(r.outstanding)}</strong> ημέρες.</p>
    <div class="grid g3"><div><label>Ημέρες που εκκαθαρίζονται</label><input id="sd-days" inputmode="decimal" value="${String(r.outstanding).replace(".", ",")}"></div>
      <div><label>Ποσό (€)</label><input id="sd-amount" inputmode="decimal" placeholder="όπως το υπολόγισε το λογιστήριο"></div>
      <div><label>Ημερομηνία πληρωμής</label><input type="date" id="sd-date" value="${athensToday()}"></div></div>
    <label>Παραστατικό (προαιρετικό)</label><input type="file" id="sd-doc" accept=".pdf,.jpg,.jpeg,.png,.webp">
    <label>Σημείωση</label><input id="sd-note" maxlength="300">
    <p id="sd-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="sd-ok">Καταχώριση πληρωμής</button></div>`, {
    onOpen() {
      $("#sd-ok").onclick = async () => {
        const btn = $("#sd-ok"); btn.disabled = true;
        try {
          const f = $("#sd-doc").files[0];
          const doc = f ? await fileToPayload(f) : null;
          await S.api.leaveSettle(r.employee_code, r.leave_year, Number($("#sd-days").value.replace(",", ".")), Number($("#sd-amount").value.replace(/\./g, "").replace(",", ".")),
            $("#sd-date").value, doc ? { name: doc.name, mime: doc.mime, data: doc.data } : null, $("#sd-note").value);
          closeDialog(); toast("Η πληρωμή εκκαθάρισης καταχωρίστηκε."); reload();
        } catch (e) { $("#sd-m").textContent = e.message; btn.disabled = false; }
      };
    },
  });
}

async function holidaysTab(body) {
  const list = await S.api.holidays();
  const y = Number(athensToday().slice(0, 4));
  body.innerHTML = `<div class="card"><div class="card-head"><h3>Αργίες</h3></div>
    <p class="muted small">Οι αργίες δεν χρεώνονται ως ημέρες κανονικής άδειας. Ελέγξτε τη λίστα κάθε έτος (κινητές εορτές).</p>
    <div class="table-wrap" style="margin-top:10px;max-height:420px"><table><thead><tr><th>Ημερομηνία</th><th>Αργία</th><th></th></tr></thead><tbody>
    ${list.filter((x) => Number(x.day.slice(0, 4)) >= y - 1).map((x) => `<tr><td>${dmy(x.day)}</td><td>${h(x.label)}</td><td style="text-align:right"><button class="btn sm ghost" data-del="${x.day}">Αφαίρεση</button></td></tr>`).join("")}
    </tbody></table></div>
    <form class="row-actions" id="hl-add" style="margin-top:12px;flex-wrap:nowrap"><input type="date" required id="hl-d" style="width:auto"><input required id="hl-l" placeholder="Ονομασία" maxlength="80"><button class="btn">Προσθήκη</button></form></div>`;
  $("#hl-add").onsubmit = async (e) => { e.preventDefault(); try { await S.api.addHoliday($("#hl-d").value, $("#hl-l").value.trim()); holidaysTab(body); } catch (err) { toast(err.message, true); } };
  $$("[data-del]", body).forEach((b) => (b.onclick = async () => { try { await S.api.removeHoliday(b.dataset.del); holidaysTab(body); } catch (err) { toast(err.message, true); } }));
}

// ═══════════════════════ Απαντήσεις (αδιάβαστες ενημερώσεις) ═══════════════════════
export async function refreshAnswers() {
  if (S.api?.mode === "demo" || !can.requests()) return 0;
  return await S.api.notifCount();
}

export async function answers(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Απαντήσεις"));
  const all = params.get("all") === "1";
  const list = await S.api.notifList(all);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Προσωπικό</div><h1>Απαντήσεις${!all && list.length ? ` <span class="badge b-pending">${list.length}</span>` : ""}</h1>
    <p class="muted">Νέες αποφάσεις και απαντήσεις της Γενικής Διευθύντριας ή του HR στα αιτήματα του καταστήματός σας. Κάθε ενημέρωση χαρακτηρίζεται διαβασμένη όταν ανοίξετε το αίτημα.</p></div>
    <a class="btn" href="#/answers${all ? "" : "?all=1"}">${all ? "Μόνο αδιάβαστες" : "Όλες (και διαβασμένες)"}</a></div>
  <div class="card">${list.length ? list.map((n) => `<a class="list-item click ${n.read_at ? "" : "unread"}" href="#/request?id=${h(n.request_id)}" style="text-decoration:none">
      <div class="grow"><strong>${h(n.title)}</strong><div class="muted small">${h(n.ref)} · ${h(n.store)} · ${athens(n.created_at)}${n.read_at ? ` · διαβάστηκε ${athens(n.read_at)}` : ""}</div></div>
      ${n.read_at ? "" : `<span class="badge b-info">Νέα</span>`}</a>`).join("")
    : `<div class="empty"><div class="big">✓</div>${all ? "Δεν υπάρχουν ενημερώσεις." : "Δεν υπάρχουν αδιάβαστες απαντήσεις."}</div>`}</div>`;
}

// ═══════════════════════ Εργασίες HR / λογιστηρίου ═══════════════════════
export async function tasks() {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Εργασίες"));
  const list = await S.api.myTasks();
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Προσωπικό</div><h1>Εργασίες μου</h1>
    <p class="muted">Εξειδικευμένες ενέργειες ${role() === "accounting" ? "λογιστηρίου" : "HR"} σε εγκεκριμένα αιτήματα. Παρακολουθούνται χωριστά από την υλοποίηση του manager.</p></div></div>
  <div class="card">${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Αίτημα</th><th>Εργαζόμενος</th><th>Ενέργεια</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
    ${list.map((t) => `<tr><td class="num"><strong>${h(t.ref)}</strong><span class="sub">${h(CATEGORIES[t.category] || t.category)}</span></td><td>${h(t.employee_name)}<span class="sub">${h(t.store)}</span></td>
      <td class="small">${h(t.description)}<span class="sub">${h(t.created_by)} · ${athens(t.created_at)}</span></td><td>${t.status === "done" ? `<span class="badge b-signed">Ολοκληρώθηκε</span>` : `<span class="badge b-pending">Ανοιχτή</span>`}</td>
      <td class="acts" style="text-align:right">${t.status === "open" ? `<button class="btn sm primary" data-done="${t.id}">Ολοκλήρωση</button>` : ""}</td></tr>`).join("")}
    </tbody></table></div>` : `<div class="empty">Δεν υπάρχουν εργασίες.</div>`}</div>`;
  $$("[data-done]").forEach((b) => (b.onclick = async () => {
    const note = await confirmBox("Ολοκλήρωση εργασίας", "Σύντομη σημείωση (προαιρετικά).", { ok: "Ολοκλήρωση", input: "Σημείωση" });
    if (note === false || note === null) return;
    try { await S.api.reqTaskDone(Number(b.dataset.done), typeof note === "string" ? note : ""); toast("Ολοκληρώθηκε."); tasks(); } catch (e) { toast(e.message, true); }
  }));
}

// Λήψη παραστατικού εκκαθάρισης
export async function downloadSettlementDoc(id) {
  try { const d = await S.api.settlementDoc(id); saveBlob(base64ToBlob(d.data, d.mime), d.name || "παραστατικό"); } catch (e) { toast(e.message, true); }
}
export { money };
