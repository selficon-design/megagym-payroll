// MEGA GYM · Ταμεία — χωριστή εφαρμογή στην ΙΔΙΑ βάση με την εφαρμογή Μισθοδοσίας / HR.
// Ίδιοι λογαριασμοί, ρόλοι και πίνακας δικαιωμάτων. Όλοι οι έλεγχοι γίνονται στη βάση· η οθόνη απλώς δεν δείχνει ό,τι δεν επιτρέπεται.
import { openDialog, closeDialog, confirmBox, toast } from "../../js/util.js";
import { $, $$, h, eur, amount, dmy, dayName, athensTime, isoDate, addDays, diffCell, readReceipt, loadScript, friendly,
  SHIFT_GR, SHIFT_SHORT, STATUS_GR, METHOD_GR, REFUND_GR, ADJ_GR } from "./common.js";

const ROLE_GR = { owner: "Γενική Διευθύντρια", hr: "HR", accounting: "Λογιστήριο", manager: "Manager", trainer: "Εκπαιδευτής" };
const ROLES = ["owner", "hr", "accounting", "manager", "trainer"];
const S = { rpc: null, me: null, lists: null, signOut: null, filters: {} };
const P = (p) => (S.me?.perms || []).includes(p);
const view = () => $("#view");
const badge = (st) => `<span class="badge ${STATUS_GR[st]?.cls || "b-missing"}">${STATUS_GR[st]?.label || "Χωρίς κλείσιμο"}</span>`;

// ═══════════════ Μενού ═══════════════
const ROUTES = [
  { id: "overview", title: "Επισκόπηση ταμείων", ico: "◫", group: "Ταμεία", render: overview, show: () => P("cash.view") },
  { id: "refunds", title: "Επιστροφές προς έγκριση", ico: "↩", group: "Ταμεία", render: refundsView, show: () => P("cash.refund_approve"), badge: "refunds" },
  { id: "corrections", title: "Διορθώσεις", ico: "✎", group: "Ταμεία", render: correctionsView, show: () => P("cash.correct_approve") || P("cash.correct_apply"), badge: "corrections" },
  { id: "links", title: "Σύνδεσμοι ρεσεψιόν", ico: "🔗", group: "Διαχείριση", render: linksView, show: () => P("cash.links") },
  { id: "perms", title: "Ρόλοι & Δικαιώματα", ico: "⚖", group: "Διαχείριση", render: permsView, show: () => P("permissions.manage") },
  { id: "settings", title: "Ρυθμίσεις ταμείων", ico: "⚙", group: "Διαχείριση", render: settingsView, show: () => P("cash.settings") },
  { id: "account", title: "Ο λογαριασμός μου", ico: "◉", group: "Λογαριασμός", render: account, show: () => true },
  { id: "day", title: "Ημέρα ταμείου", group: "", render: dayView, show: () => P("cash.view"), hidden: true, parent: "overview" },
];
const counts = { refunds: 0, corrections: 0 };
function parseHash() { const [p, q] = location.hash.replace(/^#\/?/, "").split("?"); return { id: p || "", params: new URLSearchParams(q || "") }; }
function drawNav() {
  let html = "", g = "";
  for (const r of ROUTES.filter((r) => r.show() && !r.hidden)) {
    if (r.group !== g) { g = r.group; html += `<div class="nav-group">${g}</div>`; }
    const n = r.badge ? counts[r.badge] : 0;
    html += `<a href="#/${r.id}" data-id="${r.id}"><span class="ico">${r.ico}</span>${r.title}${n ? `<span class="count hot">${n}</span>` : ""}</a>`;
  }
  html += `<div class="nav-group">Άλλες εφαρμογές</div><a href="../" data-ext><span class="ico">↗</span>Μισθοδοσία / HR</a>`;
  $("#nav").innerHTML = html;
  const { id } = parseHash(); const cur = ROUTES.find((r) => r.id === id)?.parent || id;
  $$("#nav a[data-id]").forEach((a) => a.classList.toggle("active", a.dataset.id === cur));
}
async function refreshCounts() {
  counts.refunds = P("cash.refund_approve") ? (await S.rpc("cash_refunds_pending").catch(() => [])).length : 0;
  counts.corrections = P("cash.correct_approve") || P("cash.correct_apply")
    ? (await S.rpc("cash_corrections_pending").catch(() => [])).filter((c) => (P("cash.correct_approve") && c.status === "pending") || (P("cash.correct_apply") && c.status === "approved")).length : 0;
  drawNav();
}
let seq = 0;
async function route() {
  const { id, params } = parseHash();
  const r = ROUTES.find((x) => x.id === id && x.show()) || ROUTES.find((x) => x.show() && !x.hidden);
  $("#app").classList.remove("menu-open"); closeDialog();
  $("#page-title").textContent = r.title; $("#page-sub").textContent = "";
  drawNav();
  const my = ++seq;
  view().innerHTML = `<div class="empty"><div class="spinner"></div></div>`;
  try { await r.render(params); }
  catch (e) {
    if (my !== seq) return;
    console.error(e);
    view().innerHTML = `<div class="card"><div class="empty"><div class="big">⚠︎</div><strong>Δεν φορτώθηκαν τα δεδομένα</strong><p class="muted" style="margin-top:6px">${h(friendly(e))}</p><button class="btn" style="margin-top:14px" id="retry">Δοκιμή ξανά</button></div></div>`;
    $("#retry").onclick = route;
  }
  refreshCounts();
}
const go = (hash) => { if (location.hash === hash) route(); else location.hash = hash; };
const act = (fn, ok) => async (...a) => { try { await fn(...a); if (ok) toast(ok); closeDialog(); route(); } catch (e) { toast(friendly(e), true); } };

// ═══════════════ Επισκόπηση ═══════════════
function diffs(s) {
  const parts = [["unexplained_cash", "Μετρητά"], ["unexplained_cards", "Κάρτες"], ["unexplained_iris", "IRIS"]];
  if (parts.some(([k]) => s[k] === null)) return `<span class="muted small">λείπουν ποσά SoftOne</span>`;
  const bad = parts.filter(([k]) => Math.abs(Number(s[k])) >= 0.005);
  return bad.length ? bad.map(([k, l]) => `<span class="small">${l}</span> ${diffCell(s[k])}`).join("<br>") : `<span class="t-ok small">✓ καμία</span>`;
}
async function overview(params) {
  const today = S.lists.today;
  const F = S.filters;
  F.from ??= today.slice(0, 8) + "01"; F.to ??= today; F.store ??= ""; F.only ??= "all";
  const rows = await S.rpc("cash_overview", { p_from: F.from, p_to: F.to, p_store: F.store || null });
  // Ημέρες χωρίς κλείσιμο (έως σήμερα, για διάστημα έως 62 ημερών)
  const stores = F.store ? [F.store] : S.lists.stores;
  const have = new Set(rows.map((r) => r.store + "|" + r.day));
  const missing = [];
  // μόνο από την πρώτη καταχωρισμένη ημέρα κάθε καταστήματος (όχι για την περίοδο πριν από την έναρξη των Ταμείων)
  const first = {}; for (const r of rows) if (!first[r.store] || r.day < first[r.store]) first[r.store] = r.day;
  for (let d = F.to > today ? today : F.to, n = 0; d >= F.from && n < 62; d = addDays(d, -1), n++)
    for (const st of stores) if (first[st] && d > first[st] && !have.has(st + "|" + d)) missing.push({ store: st, day: d, status: "none", shifts: [], sum: {} });
  const unexplained = (r) => ["unexplained_cash", "unexplained_cards", "unexplained_iris"].some((k) => r.sum[k] !== null && r.sum[k] !== undefined && Math.abs(Number(r.sum[k])) >= 0.005);
  const all = [...rows, ...missing].sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : a.store.localeCompare(b.store, "el")));
  const filt = { all: () => true, open: (r) => r.status === "open" || r.status === "none", confirmed: (r) => r.status === "confirmed", diff: unexplained, refunds: (r) => r.sum.refunds_pending > 0 };
  const list = all.filter(filt[F.only]);
  const n = (f) => all.filter(f).length;
  const toDeposit = rows.reduce((s, r) => s + Number(r.sum.deposit_left || 0), 0);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Κλείσιμο ταμείου</div><h1>Επισκόπηση ταμείων</h1>
    <p class="muted">Ένα φυσικό ταμείο ανά κατάστημα: πρωινό κλείσιμο 16:00, βραδινό και τυχόν συμπληρωματικό. Η ρεσεψιόν υποβάλλει, ο manager ελέγχει, το λογιστήριο κλειδώνει.</p></div>
    <div class="row-actions">${P("cash.manage") ? `<button class="btn primary" id="ov-new">+ Καταχώριση ημέρας</button>` : ""}<button class="btn" id="ov-xls">⇩ Excel</button></div></div>
  <div class="grid g4">
    <div class="card kpi warn"><div class="label">Ανοιχτές / χωρίς κλείσιμο</div><div class="value num">${n(filt.open)}</div><div class="hint">περιμένουν ρεσεψιόν ή manager</div></div>
    <div class="card kpi"><div class="label">Προς λογιστήριο</div><div class="value num">${n(filt.confirmed)}</div><div class="hint">επιβεβαιωμένες από manager</div></div>
    <div class="card kpi bad"><div class="label">Με ανεξήγητη διαφορά</div><div class="value num">${n(unexplained)}</div><div class="hint">μετρητά, κάρτες ή IRIS</div></div>
    <div class="card kpi ok"><div class="label">Μετρητά προς κατάθεση</div><div class="value num" style="font-size:24px">${eur(toDeposit)}</div><div class="hint">υπόλοιπο χωρίς καταχωρισμένη κατάθεση</div></div>
  </div>
  <div class="card" style="margin-top:16px">
    <div class="toolbar">
      <label class="tb-l">Από<input type="date" id="ov-from" value="${F.from}" max="${today}"></label>
      <label class="tb-l">Έως<input type="date" id="ov-to" value="${F.to}" max="${today}"></label>
      ${S.lists.stores.length > 1 ? `<select id="ov-store"><option value="">Όλα τα καταστήματα</option>${S.lists.stores.map((s) => `<option ${F.store === s ? "selected" : ""}>${h(s)}</option>`).join("")}</select>` : ""}
      <div class="chips">${[["all", "Όλες"], ["open", "Ανοιχτές"], ["confirmed", "Προς λογιστήριο"], ["diff", "Με διαφορά"], ["refunds", "Επιστροφές σε αναμονή"]].map(([k, l]) => `<button class="chip ${F.only === k ? "on" : ""}" data-only="${k}">${l}<span class="n">${n(filt[k])}</span></button>`).join("")}</div>
    </div>
    ${list.length ? `<div class="table-wrap"><table class="cash-table"><thead><tr><th>Ημέρα</th><th>Κατάστημα</th><th>Κλεισίματα</th><th class="r">Προς κατάθεση</th><th>Ανεξήγητες διαφορές</th><th class="r">Live Pay</th><th>Κατάσταση</th></tr></thead><tbody>
      ${list.map((r) => `<tr class="click" ${r.id ? `data-id="${r.id}"` : `data-store="${h(r.store)}" data-day="${r.day}"`}>
        <td><strong>${dmy(r.day)}</strong><span class="sub">${dayName(r.day)}</span></td><td>${h(r.store)}</td>
        <td><span class="shifts">${["morning", "evening"].map((s) => `<span class="sh ${r.shifts.includes(s) ? "on" : ""}" title="${SHIFT_GR[s]}">${SHIFT_SHORT[s]}</span>`).join("")}${r.shifts.filter((s) => s === "supplement").map(() => `<span class="sh on sup" title="Συμπληρωματικό">Σ</span>`).join("")}</span></td>
        <td class="r num">${r.id ? eur(r.sum.cash_to_deposit) : "—"}</td>
        <td>${r.id ? diffs(r.sum) : ""}</td>
        <td class="r num">${r.id && r.sum.livepay_count ? `${eur(r.sum.livepay_total)}<span class="sub">${r.sum.livepay_matched}/${r.sum.livepay_count} στην τράπεζα</span>` : "—"}</td>
        <td>${badge(r.status)}${r.sum.refunds_pending ? `<span class="sub t-warn">${r.sum.refunds_pending} επιστροφή σε αναμονή</span>` : ""}${r.correction ? `<span class="sub t-warn">αίτημα διόρθωσης</span>` : ""}</td></tr>`).join("")}
    </tbody></table></div>
    <p class="muted small" style="margin-top:8px">Οι διαφορές είναι οι <strong>ανεξήγητες</strong>, δηλαδή μετά τις προσαρμογές με αιτιολογία. Κλεισίματα: Π = πρωινό, Β = βραδινό, Σ = συμπληρωματικό.</p>`
    : `<div class="empty"><div class="big">◫</div>Δεν υπάρχουν ημέρες για αυτά τα φίλτρα.</div>`}
  </div>`;
  const reload = () => { F.from = $("#ov-from").value || F.from; F.to = $("#ov-to").value || F.to; F.store = $("#ov-store")?.value || ""; route(); };
  $("#ov-from").onchange = $("#ov-to").onchange = reload;
  $("#ov-store") && ($("#ov-store").onchange = reload);
  $$("[data-only]").forEach((b) => (b.onclick = () => { F.only = b.dataset.only; route(); }));
  $$("tr.click").forEach((tr) => (tr.onclick = async () => {
    if (tr.dataset.id) return go(`#/day?id=${tr.dataset.id}`);
    if (!P("cash.manage")) return toast("Δεν υπάρχει κλείσιμο για αυτή την ημέρα.");
    if (!(await confirmBox("Καταχώριση ημέρας", `Δεν υπάρχει κλείσιμο για ${tr.dataset.store}, ${dmy(tr.dataset.day)}. Να ανοίξει η ημέρα για καταχώριση από την εφαρμογή;`, { ok: "Άνοιγμα ημέρας" }))) return;
    try { const r = await S.rpc("cash_day_open", { p_store: tr.dataset.store, p_day: tr.dataset.day }); go(`#/day?id=${r.id}`); } catch (e) { toast(friendly(e), true); }
  }));
  $("#ov-new") && ($("#ov-new").onclick = () => openDialog(`<div class="dlg-head"><h2>Καταχώριση ημέρας</h2></div>
    <p class="muted">Για κλείσιμο που δεν υποβλήθηκε από τον σύνδεσμο της ρεσεψιόν (π.χ. από χαρτί).</p>
    <label>Κατάστημα</label><select id="nd-store">${S.lists.stores.map((s) => `<option>${h(s)}</option>`).join("")}</select>
    <label>Ημέρα</label><input type="date" id="nd-day" value="${today}" max="${today}">
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="nd-ok">Άνοιγμα</button></div>`, {
    onOpen() { $("#nd-ok").onclick = async () => { try { const r = await S.rpc("cash_day_open", { p_store: $("#nd-store").value, p_day: $("#nd-day").value }); closeDialog(); go(`#/day?id=${r.id}`); } catch (e) { toast(friendly(e), true); } }; },
  }));
  $("#ov-xls").onclick = async () => {
    try {
      await loadScript("../vendor/xlsx.js"); const X = window.XLSX;
      const head = ["Ημέρα", "Κατάστημα", "Κατάσταση", "Πρωινό (συρτάρι)", "Βραδινό (συρτάρι)", "Συμπληρωματικό", "Προς κατάθεση", "Έξοδα", "Επιστροφές μετρητών", "SoftOne-αναμενόμενα μετρητά",
        "Διαφορά μετρητών", "Προσαρμογές μετρητών", "Ανεξήγητη μετρητών", "Ανεξήγητη καρτών", "Ανεξήγητη IRIS", "Live Pay", "Κατατέθηκε", "Ελεγκτής", "Έλεγχος"];
      const data = [head, ...rows.map((r) => { const s = r.sum; return [dmy(r.day), r.store, STATUS_GR[r.status].label, s.morning_count, s.evening_count, s.supplement_cash, s.cash_to_deposit, s.expenses, s.refunds_cash, s.expected_cash,
        s.diff_cash, s.adj_cash, s.unexplained_cash, s.unexplained_cards, s.unexplained_iris, s.livepay_total, s.deposited, r.audited_name || "", athensTime(r.audited_at)].map((v) => (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v ?? "")); })];
      const wb = X.utils.book_new(); const ws = X.utils.aoa_to_sheet(data);
      ws["!cols"] = head.map((t) => ({ wch: Math.max(12, t.length + 2) }));
      X.utils.book_append_sheet(wb, ws, "Ταμεία");
      X.writeFile(wb, `tameia_${F.from}_${F.to}.xlsx`);
    } catch (e) { toast(friendly(e), true); }
  };
}

// ═══════════════ Ημέρα ταμείου ═══════════════
async function dayView(params) {
  const id = Number(params.get("id"));
  const D = await S.rpc("cash_day_get", { p_day: id });
  const s = D.sum, can = D.can, live = (x) => !x.voided_at;
  $("#page-sub").textContent = `${D.store} · ${dmy(D.day)}`;
  const voidBtn = (kind, x) => can.edit && live(x) ? `<button class="btn sm ghost" data-void="${kind}" data-id="${x.id}" title="Ακύρωση με αιτιολογία">Ακύρωση</button>` : "";
  const voided = (x) => x.voided_at ? `<span class="sub t-bad">Ακυρώθηκε: ${h(x.void_reason)} · ${h(x.voided_by)}</span>` : "";
  const trc = (x) => (x.voided_at ? `class="voided"` : "");
  const who = (v) => (String(v).startsWith("σύνδεσμος:") ? "Ρεσεψιόν (σύνδεσμος)" : String(v));
  const by = (x) => `<span class="sub">${h(who(x.created_by))} · ${athensTime(x.created_at)}</span>`;
  const sh = (x) => (x.shift ? SHIFT_GR[x.shift] : "—");
  const softEdit = can.edit;
  const fld = (k, label, hint) => `<div><label for="f-${k}">${label}</label><input id="f-${k}" data-f="${k}" inputmode="decimal" autocomplete="off" value="${D[k] === null ? "" : Number(D[k]).toFixed(2).replace(".", ",")}" ${softEdit ? "" : "disabled"} placeholder="—">${hint ? `<span class="muted small">${hint}</span>` : ""}</div>`;
  const lastEvent = [...D.events].reverse().find((e) => e.action === "returned");
  view().innerHTML = `
  <div class="page-head"><div><a href="#/overview" class="muted small" style="text-decoration:none">← Επισκόπηση</a><div class="eyebrow" style="margin-top:6px">${h(D.store)}</div>
    <h1>${dayName(D.day)} ${dmy(D.day)}</h1><div style="margin-top:8px">${badge(D.status)}</div></div>
    <div class="row-actions">
      ${can.confirm ? `<button class="btn primary" id="d-confirm">✓ Επιβεβαίωση manager</button>` : ""}
      ${can.unconfirm ? `<button class="btn" id="d-unconfirm">${P("cash.manage") ? "Αναίρεση επιβεβαίωσης" : "Επιστροφή στον manager"}</button>` : ""}
      ${can.audit ? `<button class="btn primary" id="d-lock">🔒 ${D.status === "correction" ? "Ολοκλήρωση διόρθωσης & κλείδωμα" : "Έλεγχος λογιστηρίου & κλείδωμα"}</button>` : ""}
      ${can.request_correction && !D.corrections.some((c) => ["pending", "approved"].includes(c.status)) ? `<button class="btn" id="d-corr">Αίτημα διόρθωσης</button>` : ""}
    </div></div>
  ${D.status === "open" && lastEvent && !D.events.slice(D.events.indexOf(lastEvent) + 1).some((e) => e.action === "confirm") ? `<div class="note warn" style="margin-bottom:16px"><strong>Επιστράφηκε από το λογιστήριο:</strong> ${h(lastEvent.note || "")} · ${athensTime(lastEvent.at)}</div>` : ""}
  ${D.status === "locked" ? `<div class="note" style="margin-bottom:16px">Ελέγχθηκε από <strong>${h(D.audited_name || D.audited_by)}</strong> στις ${athensTime(D.audited_at)}. Τα στοιχεία είναι κλειδωμένα· διορθώσεις γίνονται από το λογιστήριο μετά από έγκριση της Γενικής Διευθύντριας.</div>` : ""}
  ${D.status === "correction" ? `<div class="note bad" style="margin-bottom:16px">Η Γενική Διευθύντρια ενέκρινε διόρθωση: <strong>${h(D.corrections.find((c) => c.status === "approved")?.reason || "")}</strong>. Το λογιστήριο κάνει τις αλλαγές και κλειδώνει ξανά.</div>` : ""}
  ${D.corrections.filter((c) => c.status === "pending").map((c) => `<div class="note warn" style="margin-bottom:16px"><strong>Αίτημα διόρθωσης σε αναμονή έγκρισης ΓΔ:</strong> ${h(c.reason)} · ${h(c.requested_by)}
     ${can.approve_correction ? `<div class="row-actions" style="margin-top:8px"><button class="btn sm primary" data-cdec="${c.id}" data-ok="1">Έγκριση</button><button class="btn sm danger" data-cdec="${c.id}" data-ok="0">Απόρριψη</button></div>` : ""}</div>`).join("")}

  <div class="grid g4">
    <div class="card kpi ok"><div class="label">Μετρητά προς κατάθεση</div><div class="value num">${eur(s.cash_to_deposit)}</div><div class="hint">χωρίς τα ${eur(s.float)} ρέστα${Number(s.deposited) ? ` · κατατέθηκαν ${eur(s.deposited)}` : ""}</div></div>
    <div class="card kpi ${s.unexplained_cash === null ? "" : Math.abs(s.unexplained_cash) < 0.005 ? "ok" : "bad"}"><div class="label">Μετρητά · ανεξήγητη διαφορά</div><div class="value num">${s.unexplained_cash === null ? "—" : eur(s.unexplained_cash, { sign: true })}</div><div class="hint">${s.expected_cash === null ? "λείπουν τα ποσά SoftOne" : `αναμενόμενα ${eur(s.expected_cash)}`}</div></div>
    <div class="card kpi ${s.unexplained_cards === null ? "" : Math.abs(s.unexplained_cards) < 0.005 ? "ok" : "bad"}"><div class="label">Κάρτες · ανεξήγητη διαφορά</div><div class="value num">${s.unexplained_cards === null ? "—" : eur(s.unexplained_cards, { sign: true })}</div><div class="hint">POS ${eur(D.pos_cards)} · SoftOne ${eur(D.softone_cards)}</div></div>
    <div class="card kpi ${s.unexplained_iris === null ? "" : Math.abs(s.unexplained_iris) < 0.005 ? "ok" : "bad"}"><div class="label">IRIS · ανεξήγητη διαφορά</div><div class="value num">${s.unexplained_iris === null ? "—" : eur(s.unexplained_iris, { sign: true })}</div><div class="hint">IRIS ${eur(D.iris_total)} · SoftOne ${eur(D.softone_iris)}</div></div>
  </div>

  <div class="grid g2-1" style="margin-top:16px">
    <div class="card"><div class="card-head"><h3>Κλεισίματα βάρδιας</h3>${can.edit ? `<button class="btn sm" id="d-shift">+ Κλείσιμο</button>` : ""}</div>
      ${D.shifts.length ? `<div class="table-wrap"><table><thead><tr><th>Κλείσιμο</th><th class="r">Καταμέτρηση</th><th class="r">Μετρητά βάρδιας</th><th></th></tr></thead><tbody>
        ${D.shifts.map((x) => `<tr ${trc(x)}><td><strong>${SHIFT_GR[x.shift]}</strong>${x.employee_name ? ` · ${h(x.employee_name)}` : ""}${by(x)}${x.note ? `<span class="sub">«${h(x.note)}»</span>` : ""}${voided(x)}</td>
          <td class="r num">${eur(x.counted_cash)}</td><td class="r num">${eur(x.shift === "supplement" ? x.counted_cash : Math.max(x.counted_cash - D.float_amount, 0))}</td>
          <td class="acts"><div class="row-actions">${can.edit && live(x) ? `<button class="btn sm" data-fix="${x.id}">Διόρθωση</button>` : ""}${voidBtn("shift", x)}</div></td></tr>`).join("")}
      </tbody></table></div>` : `<p class="muted">Δεν έχει υποβληθεί κλείσιμο ακόμη.</p>`}
      <dl class="kv"><dt>Ταμείο έναρξης</dt><dd class="num">${eur(D.float_amount)} <span class="muted small">(αφαιρείται από κάθε καταμέτρηση πρωινού/βραδινού)</span></dd></dl>
    </div>
    <div class="card"><div class="card-head"><h3>Συμφωνία με SoftOne</h3></div>
      <table class="recon"><tbody>
        <tr><td>SoftOne μετρητά</td><td class="r num">${eur(D.softone_cash)}</td></tr>
        <tr><td>− Έξοδα ταμείου</td><td class="r num">${eur(s.expenses)}</td></tr>
        <tr><td>− Επιστροφές σε μετρητά</td><td class="r num">${eur(s.refunds_cash)}</td></tr>
        <tr class="tot"><td>= Αναμενόμενα μετρητά</td><td class="r num">${eur(s.expected_cash)}</td></tr>
        <tr><td>Μετρητά προς κατάθεση</td><td class="r num">${eur(s.cash_to_deposit)}</td></tr>
        <tr><td>Διαφορά</td><td class="r">${diffCell(s.diff_cash)}</td></tr>
        <tr><td>Προσαρμογές με αιτιολογία</td><td class="r num">${eur(s.adj_cash, { sign: true })}</td></tr>
        <tr class="tot"><td>Ανεξήγητη διαφορά</td><td class="r">${diffCell(s.unexplained_cash)}</td></tr>
      </tbody></table>
      ${Number(s.refunds_card) ? `<p class="muted small" style="margin-top:8px">Επιστροφές σε κάρτα: ${eur(s.refunds_card)} (περνούν από το POS· δεν αφαιρούνται από τα μετρητά).</p>` : ""}
    </div>
  </div>

  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Ποσά ημέρας</h3>${softEdit ? `<span class="muted small">Ο manager καταχωρίζει τα ποσά του SoftOne χειροκίνητα.</span>` : ""}</div>
    <div class="grid g3">${fld("pos_cards", "Πακέτο POS ημέρας (κάρτες)")}${fld("iris_total", "IRIS ημέρας")}<div></div>
      ${fld("softone_cash", "SoftOne · μετρητά")}${fld("softone_cards", "SoftOne · κάρτες")}${fld("softone_iris", "SoftOne · IRIS")}</div>
    <label for="f-note">Σημείωση manager</label><textarea id="f-note" ${softEdit ? "" : "disabled"} maxlength="1000" style="min-height:60px">${h(D.manager_note || "")}</textarea>
    ${softEdit ? `<div class="row-actions" style="margin-top:12px;justify-content:flex-end"><button class="btn primary" id="d-save">Αποθήκευση ποσών</button></div>` : ""}
  </div>

  ${section("Καταθέσεις πελατών — Live Pay", "livepay", can.edit, D.livepay, ["Πελάτης", "Κλείσιμο", "Ποσό", "Τράπεζα", ""], (x) => `<tr ${trc(x)}>
     <td><strong>${h(x.customer)}</strong>${by(x)}${voided(x)}</td><td>${sh(x)}</td><td class="r num">${eur(x.amount)}</td>
     <td>${x.matched_at ? `<span class="badge b-signed">Αντιστοιχίστηκε</span><span class="sub">${h(x.bank_ref || "")} · ${h(x.matched_by)} · ${athensTime(x.matched_at)}</span>` : `<span class="badge b-missing">Όχι ακόμη</span>`}</td>
     <td class="acts"><div class="row-actions">${can.match && live(x) ? `<button class="btn sm" data-match="${x.id}" data-on="${x.matched_at ? 0 : 1}">${x.matched_at ? "Αναίρεση" : "Αντιστοίχιση"}</button>` : ""}${voidBtn("livepay", x)}</div></td></tr>`)}

  ${section("Έξοδα από το ταμείο", "expense", can.edit, D.expenses, ["Περιγραφή", "Κατηγορία", "Ημερομηνία", "Ποσό", "Παραστατικό", ""], (x) => `<tr ${trc(x)}>
     <td><strong>${h(x.description)}</strong>${by(x)}${voided(x)}</td><td>${h(x.category)}</td><td>${dmy(x.expense_date)}</td><td class="r num">${eur(x.amount)}</td>
     <td><button class="btn sm" data-file="${x.file_id}">📄 Προβολή</button></td><td class="acts">${voidBtn("expense", x)}</td></tr>`)}

  ${section("Επιστροφές χρημάτων", "refund", can.edit, D.refunds, ["Πελάτης / αιτία", "Τρόπος", "Ποσό", "Έγκριση", ""], (x) => `<tr ${trc(x)}>
     <td><strong>${h(x.customer)}</strong><span class="sub">${h(x.reason)}</span>${by(x)}${voided(x)}</td><td>${METHOD_GR[x.method]}</td><td class="r num">${eur(x.amount)}</td>
     <td><span class="badge ${REFUND_GR[x.status].cls}">${REFUND_GR[x.status].label}</span><span class="sub">${x.status === "pending" ? `Ενέκρινε (δήλωση): ${h(x.approver_name)}` : `${h(x.decided_name || x.decided_by)} · ${athensTime(x.decided_at)}${x.decision_note ? " · " + h(x.decision_note) : ""}`}</span></td>
     <td class="acts"><div class="row-actions">${can.approve_refund && x.status === "pending" && live(x) ? `<button class="btn sm primary" data-rdec="${x.id}" data-ok="1">Έγκριση</button><button class="btn sm danger" data-rdec="${x.id}" data-ok="0">Απόρριψη</button>` : ""}${voidBtn("refund", x)}</div></td></tr>`)}

  ${section("Προσαρμογές (εξηγούν διαφορές)", "adjustment", can.edit, D.adjustments, ["Αιτιολογία", "Αφορά", "Ποσό", ""], (x) => `<tr ${trc(x)}>
     <td><strong>${h(x.reason)}</strong>${by(x)}${voided(x)}</td><td>${ADJ_GR[x.kind]}</td><td class="r num">${eur(x.amount, { sign: true })}</td><td class="acts">${voidBtn("adjustment", x)}</td></tr>`)}

  ${section("Καταθέσεις στην τράπεζα", "deposit", P("cash.manage") || P("cash.correct_apply"), D.deposits, ["Ημερομηνία", "Ποσό", "Απόδειξη", ""], (x) => `<tr ${trc(x)}>
     <td><strong>${dmy(x.deposit_date)}</strong>${by(x)}${voided(x)}</td><td class="r num">${eur(x.amount)}</td><td><button class="btn sm" data-file="${x.file_id}">📄 Προβολή</button></td>
     <td class="acts">${(P("cash.manage") || P("cash.correct_apply")) && live(x) ? `<button class="btn sm ghost" data-void="deposit" data-id="${x.id}">Ακύρωση</button>` : ""}</td></tr>`,
     `Υπόλοιπο προς κατάθεση: <strong class="num">${eur(s.deposit_left)}</strong>`)}

  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Χρονολόγιο</h3></div>
    <ul class="timeline">${D.events.map((e) => `<li><span class="muted small num">${athensTime(e.at)}</span> <strong>${h(EVENT_GR[e.action] || e.action)}</strong> · <span class="small">${h(String(e.actor).replace(/^σύνδεσμος:[^·]*· /, "Ρεσεψιόν · "))}</span>${e.note ? `<span class="sub">${h(e.note)}</span>` : ""}</li>`).join("") || `<li class="muted">—</li>`}</ul>
  </div>`;
  bindDay(D);
}
const EVENT_GR = {
  submit_morning: "Πρωινό κλείσιμο από τη ρεσεψιόν", submit_evening: "Βραδινό κλείσιμο από τη ρεσεψιόν", submit_supplement: "Συμπληρωματικό από τη ρεσεψιόν",
  shift_add: "Κλείσιμο από την εφαρμογή", shift_replace: "Διόρθωση κλεισίματος", confirm: "Επιβεβαίωση manager", unconfirm: "Αναίρεση επιβεβαίωσης",
  returned: "Επιστροφή στον manager από το λογιστήριο", lock: "Έλεγχος λογιστηρίου & κλείδωμα", refund_approved: "Έγκριση επιστροφής", refund_rejected: "Απόρριψη επιστροφής",
  livepay_matched: "Αντιστοίχιση Live Pay με την τράπεζα", livepay_unmatched: "Αναίρεση αντιστοίχισης Live Pay", deposit: "Κατάθεση στην τράπεζα",
  correction_requested: "Αίτημα διόρθωσης", correction_approved: "Έγκριση διόρθωσης από ΓΔ", correction_rejected: "Απόρριψη διόρθωσης από ΓΔ", correction_applied: "Διόρθωση & νέο κλείδωμα",
  void_shift: "Ακύρωση κλεισίματος", void_livepay: "Ακύρωση Live Pay", void_expense: "Ακύρωση εξόδου", void_refund: "Ακύρωση επιστροφής", void_adjustment: "Ακύρωση προσαρμογής", void_deposit: "Ακύρωση κατάθεσης",
};
function section(title, kind, canAdd, rows, cols, row, foot = "") {
  const shown = rows.filter((x) => !x.voided_at).length;
  return `<div class="card" style="margin-top:16px"><div class="card-head"><h3>${title} <span class="muted small">${shown || ""}</span></h3>${canAdd ? `<button class="btn sm" data-add="${kind}">+ Προσθήκη</button>` : ""}</div>
    ${rows.length ? `<div class="table-wrap"><table><thead><tr>${cols.map((c) => `<th class="${/Ποσό/.test(c) ? "r" : ""}">${c}</th>`).join("")}</tr></thead><tbody>${rows.map(row).join("")}</tbody></table></div>` : `<p class="muted">Καμία εγγραφή.</p>`}
    ${foot ? `<p class="small" style="margin-top:10px">${foot}</p>` : ""}</div>`;
}

function bindDay(D) {
  const id = D.id;
  const num = (v, label, opt = {}) => { const n = amount(v, opt); if (Number.isNaN(n)) throw new Error(`Μη έγκυρο ποσό: ${label}.`); return n; };
  $("#d-save") && ($("#d-save").onclick = act(async () => {
    const p = {}; for (const inp of $$("[data-f]")) p[inp.dataset.f] = num(inp.value, inp.closest("div").querySelector("label").textContent);
    p.manager_note = $("#f-note").value;
    await S.rpc("cash_day_save", { p_day: id, p_version: D.version, p });
  }, "Αποθηκεύτηκαν τα ποσά."));
  $("#d-confirm") && ($("#d-confirm").onclick = async () => {
    const s = D.sum, bad = ["unexplained_cash", "unexplained_cards", "unexplained_iris"].filter((k) => s[k] !== null && Math.abs(s[k]) >= 0.005);
    if (!(await confirmBox("Επιβεβαίωση manager", bad.length ? `Υπάρχει ανεξήγητη διαφορά (${bad.map((k) => ({ unexplained_cash: "μετρητά", unexplained_cards: "κάρτες", unexplained_iris: "IRIS" })[k]).join(", ")}). Αν γνωρίζετε την αιτία, καταχωρίστε προσαρμογή με αιτιολογία. Επιβεβαίωση και αποστολή στο λογιστήριο;` : "Τα στοιχεία της ημέρας ελέγχθηκαν και στέλνονται στο λογιστήριο.", { ok: "Επιβεβαίωση" }))) return;
    act(() => S.rpc("cash_confirm", { p_day: id, p_version: D.version }), "Η ημέρα επιβεβαιώθηκε και στάλθηκε στο λογιστήριο.")();
  });
  $("#d-unconfirm") && ($("#d-unconfirm").onclick = async () => {
    const mgr = P("cash.manage");
    const note = await confirmBox(mgr ? "Αναίρεση επιβεβαίωσης" : "Επιστροφή στον manager", mgr ? "Η ημέρα ανοίγει ξανά για αλλαγές." : "Η ημέρα επιστρέφει στον manager για διόρθωση.", { ok: mgr ? "Αναίρεση" : "Επιστροφή", input: mgr ? null : "Τι πρέπει να διορθωθεί" });
    if (!note) return;
    act(() => S.rpc("cash_unconfirm", { p_day: id, p_note: typeof note === "string" ? note : null }), "Η ημέρα άνοιξε ξανά.")();
  });
  $("#d-lock") && ($("#d-lock").onclick = async () => {
    if (!(await confirmBox("Έλεγχος λογιστηρίου", `Καταγράφεται ο έλεγχος με το όνομά σας, την ημερομηνία και την ώρα, και τα στοιχεία της ημέρας κλειδώνουν.`, { ok: "Έλεγχος & κλείδωμα" }))) return;
    act(() => S.rpc("cash_lock", { p_day: id, p_version: D.version }), "Η ημέρα ελέγχθηκε και κλείδωσε.")();
  });
  $("#d-corr") && ($("#d-corr").onclick = async () => {
    const r = await confirmBox("Αίτημα διόρθωσης", "Η Γενική Διευθύντρια εγκρίνει πρώτα τη διόρθωση· μετά την έγκριση η ημέρα ανοίγει μόνο για το λογιστήριο.", { ok: "Αποστολή αιτήματος", input: "Τι πρέπει να διορθωθεί και γιατί" });
    if (r) act(() => S.rpc("cash_correction_request", { p_day: id, p_reason: r }), "Το αίτημα στάλθηκε στη Γενική Διευθύντρια.")();
  });
  $$("[data-cdec]").forEach((b) => (b.onclick = () => decideCorrection(Number(b.dataset.cdec), b.dataset.ok === "1")));
  $$("[data-rdec]").forEach((b) => (b.onclick = () => decideRefund(Number(b.dataset.rdec), b.dataset.ok === "1")));
  $$("[data-void]").forEach((b) => (b.onclick = async () => {
    const r = await confirmBox("Ακύρωση εγγραφής", "Η εγγραφή δεν διαγράφεται· μένει στο ιστορικό ως ακυρωμένη.", { ok: "Ακύρωση εγγραφής", danger: true, input: "Αιτιολογία" });
    if (r) act(() => S.rpc("cash_item_void", { p_kind: b.dataset.void, p_id: Number(b.dataset.id), p_reason: r }), "Η εγγραφή ακυρώθηκε.")();
  }));
  $$("[data-match]").forEach((b) => (b.onclick = async () => {
    const on = b.dataset.on === "1";
    const ref = on ? await confirmBox("Αντιστοίχιση με την τράπεζα", "Η κατάθεση Live Pay βρέθηκε στην κίνηση της τράπεζας.", { ok: "Αντιστοίχιση", input: "Αναφορά τράπεζας (π.χ. αριθμός κίνησης)" }) : true;
    if (ref) act(() => S.rpc("cash_livepay_match", { p_id: Number(b.dataset.match), p_matched: on, p_bank_ref: typeof ref === "string" ? ref : null }), on ? "Αντιστοιχίστηκε." : "Η αντιστοίχιση αναιρέθηκε.")();
  }));
  $$("[data-file]").forEach((b) => (b.onclick = () => showFile(b.dataset.file)));
  $("#d-shift") && ($("#d-shift").onclick = () => shiftDialog(D));
  $$("[data-fix]").forEach((b) => (b.onclick = () => shiftDialog(D, D.shifts.find((x) => x.id === Number(b.dataset.fix)))));
  $$("[data-add]").forEach((b) => (b.onclick = () => itemDialog(D, b.dataset.add)));
}

function shiftDialog(D, old = null) {
  const used = D.shifts.filter((x) => !x.voided_at).map((x) => x.shift);
  openDialog(`<div class="dlg-head"><h2>${old ? "Διόρθωση κλεισίματος" : "Κλείσιμο βάρδιας"}</h2></div>
    <label>Κλείσιμο</label><select id="sd-shift" ${old ? "disabled" : ""}>${["morning", "evening", "supplement"].map((s) => `<option value="${s}" ${(old?.shift || "") === s ? "selected" : ""} ${!old && s !== "supplement" && used.includes(s) ? "disabled" : ""}>${SHIFT_GR[s]}</option>`).join("")}</select>
    <label>Καταμέτρηση μετρητών</label><input id="sd-c" inputmode="decimal" value="${old ? h(String(old.counted_cash).replace(".", ",")) : ""}" placeholder="0,00">
    <p class="muted small" style="margin-top:6px">Πρωινό/βραδινό: όλο το συρτάρι μαζί με τα ${eur(D.float_amount)} ρέστα. Συμπληρωματικό: μόνο τα επιπλέον μετρητά.</p>
    <label>Υπάλληλος ρεσεψιόν</label><input id="sd-e" value="${h(old?.employee_name || "")}" maxlength="120">
    <label>Σημείωση</label><input id="sd-n" value="${h(old?.note || "")}" maxlength="500">
    ${old ? `<label>Αιτιολογία διόρθωσης</label><input id="sd-r" maxlength="300">` : ""}
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="sd-ok">Αποθήκευση</button></div>`, {
    onOpen() {
      $("#sd-ok").onclick = act(async () => {
        const c = amount($("#sd-c").value); if (c === null || Number.isNaN(c)) throw new Error("Συμπληρώστε την καταμέτρηση.");
        const p = { shift: old?.shift || $("#sd-shift").value, counted_cash: c, employee_name: $("#sd-e").value, note: $("#sd-n").value };
        if (old) { p.replace_id = old.id; p.reason = $("#sd-r").value; }
        await S.rpc("cash_shift_save", { p_day: D.id, p });
      }, "Αποθηκεύτηκε.");
    },
  });
}

function itemDialog(D, kind) {
  const shiftSel = `<label>Κλείσιμο</label><select id="it-shift"><option value="">—</option>${["morning", "evening", "supplement"].map((s) => `<option value="${s}">${SHIFT_GR[s]}</option>`).join("")}</select>`;
  const file = (lbl) => `<label>${lbl}</label><input type="file" id="it-file" accept="image/*,application/pdf" capture="environment">`;
  const forms = {
    livepay: ["Κατάθεση πελάτη — Live Pay", `<label>Πελάτης</label><input id="it-customer" maxlength="120"><label>Ποσό</label><input id="it-amount" inputmode="decimal" placeholder="0,00">${shiftSel}`],
    expense: ["Έξοδο από το ταμείο", `<div class="grid g2"><div><label>Ποσό</label><input id="it-amount" inputmode="decimal" placeholder="0,00"></div><div><label>Ημερομηνία</label><input type="date" id="it-date" value="${D.day}" max="${D.day}"></div></div>
       <label>Κατηγορία</label><select id="it-category"><option value="">— επιλέξτε —</option>${S.lists.categories.filter((c) => c.active).map((c) => `<option>${h(c.name)}</option>`).join("")}</select>
       <label>Περιγραφή</label><input id="it-description" maxlength="300">${shiftSel}${file("Φωτογραφία παραστατικού (υποχρεωτική)")}`],
    refund: ["Επιστροφή χρημάτων", `<div class="grid g2"><div><label>Ποσό</label><input id="it-amount" inputmode="decimal" placeholder="0,00"></div><div><label>Τρόπος</label><select id="it-method"><option value="cash">Μετρητά</option><option value="card">Κάρτα</option></select></div></div>
       <label>Πελάτης</label><input id="it-customer" maxlength="120"><label>Αιτία</label><input id="it-reason" maxlength="300">
       <label>Ενέκρινε</label><select id="it-approver"><option value="">— επιλέξτε —</option>${S.lists.approvers.map((a) => `<option value="${h(a.id)}">${h(a.name)}</option>`).join("")}</select>${shiftSel}
       <p class="muted small" style="margin-top:8px">Η επιστροφή μένει «σε αναμονή» μέχρι να την εγκρίνει στην εφαρμογή όποιος έχει το δικαίωμα έγκρισης.</p>`],
    adjustment: ["Προσαρμογή που εξηγεί διαφορά", `<label>Αφορά</label><select id="it-kind"><option value="cash">Μετρητά</option><option value="cards">Κάρτες</option><option value="iris">IRIS</option></select>
       <label>Ποσό (με πρόσημο)</label><input id="it-amount" inputmode="decimal" placeholder="π.χ. 15,00 ή -2,50">
       <p class="muted small" style="margin-top:6px">Θετικό ποσό: εξηγεί πλεόνασμα (π.χ. είσπραξη που δεν πέρασε στο SoftOne). Αρνητικό: εξηγεί έλλειμμα.</p>
       <label>Αιτιολογία</label><input id="it-reason" maxlength="300">`],
    deposit: ["Κατάθεση στην τράπεζα", `<div class="grid g2"><div><label>Ημερομηνία κατάθεσης</label><input type="date" id="it-date" value="${S.lists.today}" min="${D.day}" max="${S.lists.today}"></div><div><label>Ποσό</label><input id="it-amount" inputmode="decimal" placeholder="0,00" value="${Number(D.sum.deposit_left) > 0 ? h(String(D.sum.deposit_left).replace(".", ",")) : ""}"></div></div>${file("Φωτογραφία απόδειξης κατάθεσης (υποχρεωτική)")}`],
  };
  const [title, html] = forms[kind];
  openDialog(`<div class="dlg-head"><h2>${title}</h2></div>${html}<div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="it-ok">Αποθήκευση</button></div>`, {
    onOpen() {
      $("#it-ok").onclick = async () => {
        const b = $("#it-ok"); b.disabled = true;
        try {
          const v = (k) => $("#it-" + k)?.value ?? null;
          const a = amount(v("amount"), { signed: kind === "adjustment" });
          if (a === null || Number.isNaN(a) || (kind !== "adjustment" && !(a > 0))) throw new Error("Συμπληρώστε έγκυρο ποσό.");
          const p = { amount: a, shift: v("shift") || null };
          if (kind === "livepay") p.customer = v("customer");
          if (kind === "expense") Object.assign(p, { date: v("date"), category: v("category"), description: v("description") });
          if (kind === "refund") Object.assign(p, { method: v("method"), customer: v("customer"), reason: v("reason"), approver: v("approver") });
          if (kind === "adjustment") Object.assign(p, { kind: v("kind"), reason: v("reason") });
          if (kind === "deposit") p.date = v("date");
          if (kind === "expense" || kind === "deposit") { const f = $("#it-file").files[0]; if (!f) throw new Error("Επισυνάψτε φωτογραφία."); p.file = await readReceipt(f); }
          if (kind === "deposit") await S.rpc("cash_deposit_add", { p_day: D.id, p });
          else await S.rpc("cash_item_add", { p_day: D.id, p_kind: kind, p });
          toast("Αποθηκεύτηκε."); closeDialog(); route();
        } catch (e) { toast(friendly(e), true); b.disabled = false; }
      };
    },
  });
}

async function showFile(fid) {
  try {
    const f = await S.rpc("cash_file_get", { p_id: fid });
    const bin = atob(f.data), u8 = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([u8], { type: f.mime }));
    if (/^image\//.test(f.mime) && f.mime !== "image/heic") openDialog(`<div class="dlg-head"><h2>${h(f.filename)}</h2></div><img src="${url}" alt="" style="max-width:100%;border-radius:8px"><div class="dlg-foot"><a class="btn" href="${url}" download="${h(f.filename)}">⇩ Λήψη</a><button class="btn primary" data-close>Κλείσιμο</button></div>`, { wide: true });
    else openDialog(`<div class="dlg-head"><h2>${h(f.filename)}</h2></div><p class="muted">Το αρχείο ανοίγει σε νέα καρτέλα ή κατεβαίνει.</p><div class="dlg-foot"><a class="btn primary" href="${url}" target="_blank" rel="noopener">Άνοιγμα</a><a class="btn" href="${url}" download="${h(f.filename)}">⇩ Λήψη</a></div>`);
  } catch (e) { toast(friendly(e), true); }
}

async function decideRefund(rid, ok) {
  const note = ok ? await confirmBox("Έγκριση επιστροφής", "Καταγράφεται η έγκριση με το όνομά σας.", { ok: "Έγκριση" }) : await confirmBox("Απόρριψη επιστροφής", "Η επιστροφή δεν θα αφαιρεθεί από τα μετρητά.", { ok: "Απόρριψη", danger: true, input: "Αιτιολογία" });
  if (note) act(() => S.rpc("cash_refund_decide", { p_id: rid, p_approve: ok, p_note: typeof note === "string" ? note : null }), ok ? "Η επιστροφή εγκρίθηκε." : "Η επιστροφή απορρίφθηκε.")();
}
async function decideCorrection(cid, ok) {
  const note = ok ? await confirmBox("Έγκριση διόρθωσης", "Η ημέρα ξεκλειδώνει μόνο για το λογιστήριο, που κάνει τη διόρθωση και κλειδώνει ξανά.", { ok: "Έγκριση" }) : await confirmBox("Απόρριψη διόρθωσης", "Η ημέρα μένει κλειδωμένη.", { ok: "Απόρριψη", danger: true, input: "Αιτιολογία" });
  if (note) act(() => S.rpc("cash_correction_decide", { p_id: cid, p_approve: ok, p_note: typeof note === "string" ? note : null }), ok ? "Η διόρθωση εγκρίθηκε." : "Η διόρθωση απορρίφθηκε.")();
}

// ═══════════════ Επιστροφές & διορθώσεις ═══════════════
async function refundsView() {
  const rows = await S.rpc("cash_refunds_pending");
  view().innerHTML = `<div class="page-head"><div><div class="eyebrow">Ταμεία</div><h1>Επιστροφές προς έγκριση</h1>
    <p class="muted">Η ημέρα δεν επιβεβαιώνεται ούτε κλειδώνει όσο υπάρχουν επιστροφές σε αναμονή.</p></div></div>
    <div class="card">${rows.length ? `<div class="table-wrap"><table><thead><tr><th>Ημέρα</th><th>Πελάτης / αιτία</th><th>Τρόπος</th><th class="r">Ποσό</th><th>Δηλώθηκε ότι ενέκρινε</th><th></th></tr></thead><tbody>
      ${rows.map((r) => `<tr><td><a href="#/day?id=${r.day_id}"><strong>${dmy(r.day)}</strong></a><span class="sub">${h(r.store)}</span></td><td><strong>${h(r.customer)}</strong><span class="sub">${h(r.reason)}</span></td>
        <td>${METHOD_GR[r.method]}</td><td class="r num">${eur(r.amount)}</td><td>${h(r.approver_name)}${r.mine ? ` <span class="badge b-role">εσείς</span>` : ""}</td>
        <td class="acts"><div class="row-actions"><button class="btn sm primary" data-rdec="${r.id}" data-ok="1">Έγκριση</button><button class="btn sm danger" data-rdec="${r.id}" data-ok="0">Απόρριψη</button></div></td></tr>`).join("")}
    </tbody></table></div>` : `<div class="empty"><div class="big">✓</div>Καμία επιστροφή σε αναμονή.</div>`}</div>`;
  $$("[data-rdec]").forEach((b) => (b.onclick = () => decideRefund(Number(b.dataset.rdec), b.dataset.ok === "1")));
}
async function correctionsView() {
  const rows = await S.rpc("cash_corrections_pending");
  view().innerHTML = `<div class="page-head"><div><div class="eyebrow">Ταμεία</div><h1>Διορθώσεις κλειδωμένων ημερών</h1>
    <p class="muted">Το λογιστήριο ζητά τη διόρθωση, η Γενική Διευθύντρια την εγκρίνει, το λογιστήριο τη διορθώνει και κλειδώνει ξανά. Όλα μένουν στο ιστορικό.</p></div></div>
    <div class="card">${rows.length ? `<div class="table-wrap"><table><thead><tr><th>Ημέρα</th><th>Αιτιολογία</th><th>Ζήτησε</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${rows.map((r) => `<tr><td><a href="#/day?id=${r.day_id}"><strong>${dmy(r.day)}</strong></a><span class="sub">${h(r.store)}</span></td><td>${h(r.reason)}</td><td>${h(r.requested_by)}<span class="sub">${athensTime(r.requested_at)}</span></td>
        <td>${r.status === "pending" ? `<span class="badge b-pending">Περιμένει ΓΔ</span>` : `<span class="badge b-voided">Εγκρίθηκε · προς διόρθωση</span>`}</td>
        <td class="acts"><div class="row-actions">${r.status === "pending" && P("cash.correct_approve") ? `<button class="btn sm primary" data-cdec="${r.id}" data-ok="1">Έγκριση</button><button class="btn sm danger" data-cdec="${r.id}" data-ok="0">Απόρριψη</button>` : `<a class="btn sm" href="#/day?id=${r.day_id}">Άνοιγμα ημέρας</a>`}</div></td></tr>`).join("")}
    </tbody></table></div>` : `<div class="empty"><div class="big">✓</div>Κανένα ανοιχτό αίτημα διόρθωσης.</div>`}</div>`;
  $$("[data-cdec]").forEach((b) => (b.onclick = () => decideCorrection(Number(b.dataset.cdec), b.dataset.ok === "1")));
}

// ═══════════════ Σύνδεσμοι ρεσεψιόν ═══════════════
async function linksView() {
  const L = await S.rpc("cashlink_list");
  const stores = S.lists.stores;
  view().innerHTML = `<div class="page-head"><div><div class="eyebrow">Διαχείριση</div><h1>Σύνδεσμοι ταμείου ρεσεψιόν</h1>
    <p class="muted">Ένας σύνδεσμος ανά κατάστημα για το κλείσιμο ταμείου από τη ρεσεψιόν, χωρίς λογαριασμό. Είναι χωριστός από τον σύνδεσμο στατιστικών.
    Ο σύνδεσμος εμφανίζεται <strong>μόνο μία φορά</strong>, όταν δημιουργείται· η βάση κρατά μόνο κρυπτογραφημένο αποτύπωμα. Ανοίξτε τον στον υπολογιστή της ρεσεψιόν και προσθέστε τον στα αγαπημένα.</p></div></div>
    <div class="card"><div class="table-wrap"><table><thead><tr><th>Κατάστημα</th><th>Κατάσταση</th><th>Δημιουργία</th><th class="r">Υποβολές</th><th>Τελευταία χρήση</th><th></th></tr></thead><tbody>
    ${stores.map((st) => { const a = L.find((l) => l.store === st && l.status === "active"); return `<tr><td><strong>${h(st)}</strong></td>
      <td>${a ? `<span class="badge b-signed">Ενεργός</span>` : `<span class="badge b-missing">Χωρίς σύνδεσμο</span>`}</td>
      <td>${a ? `${athensTime(a.created_at)}<span class="sub">${h(a.created_by)}</span>` : "—"}</td><td class="r num">${a ? a.submissions : "—"}</td><td>${a?.last_used_at ? athensTime(a.last_used_at) : "—"}</td>
      <td class="acts"><div class="row-actions"><button class="btn sm ${a ? "" : "primary"}" data-mk="${h(st)}">${a ? "Νέος σύνδεσμος" : "Δημιουργία"}</button>${a ? `<button class="btn sm danger" data-rv="${h(st)}">Ανάκληση</button>` : ""}</div></td></tr>`; }).join("")}
    </tbody></table></div></div>`;
  $$("[data-mk]").forEach((b) => (b.onclick = async () => {
    const st = b.dataset.mk, had = L.some((l) => l.store === st && l.status === "active");
    if (had && !(await confirmBox("Νέος σύνδεσμος", `Ο σημερινός σύνδεσμος του καταστήματος ${st} θα σταματήσει να λειτουργεί αμέσως.`, { ok: "Δημιουργία νέου", danger: true }))) return;
    try {
      const r = await S.rpc("cashlink_create", { p_store: st });
      const url = new URL("k.html", location.href).href.split("#")[0] + "#" + r.token;
      openDialog(`<div class="dlg-head"><h2>Σύνδεσμος ταμείου · ${h(st)}</h2></div>
        <p class="note warn">Αντιγράψτε τον τώρα: δεν θα εμφανιστεί ξανά. Αν χαθεί, φτιάξτε νέο.</p>
        <label>Σύνδεσμος</label><input id="lk-url" readonly value="${h(url)}">
        <div class="dlg-foot"><button class="btn" id="lk-copy">Αντιγραφή</button><button class="btn primary" data-close>Τέλος</button></div>`, {
        onOpen(d) { $("#lk-url").select(); $("#lk-copy").onclick = async () => { try { await navigator.clipboard.writeText(url); toast("Αντιγράφηκε."); } catch { $("#lk-url").select(); document.execCommand("copy"); toast("Αντιγράφηκε."); } }; d.addEventListener("close", () => route(), { once: true }); },
      });
    } catch (e) { toast(friendly(e), true); }
  }));
  $$("[data-rv]").forEach((b) => (b.onclick = async () => {
    const r = await confirmBox("Ανάκληση συνδέσμου", `Ο σύνδεσμος του καταστήματος ${b.dataset.rv} σταματά αμέσως.`, { ok: "Ανάκληση", danger: true, input: "Αιτιολογία" });
    if (r) act(() => S.rpc("cashlink_revoke", { p_store: b.dataset.rv, p_reason: r }), "Ο σύνδεσμος ανακλήθηκε.")();
  }));
}

// ═══════════════ Ρόλοι & Δικαιώματα (ενότητα Ταμεία, ίδιος πίνακας με την εφαρμογή HR) ═══════════════
async function permsView() {
  const M = await S.rpc("permissions_matrix");
  const perms = M.permissions.filter((p) => p.module === "Ταμεία");
  const draft = JSON.parse(JSON.stringify(M.grants));
  const SCOPE_GR = { all: "Όλα", own_store: "Μόνο το δικό του", assigned: "Ανά χρήστη" };
  const locked = (r, p) => !!p.fixed_roles;
  const changes = () => { const out = []; for (const r of ROLES) for (const p of perms) if (draft[r][p.code] !== M.grants[r][p.code]) out.push({ role: r, perm: p.code, allowed: draft[r][p.code] }); return out; };
  const logs = M.log.filter((l) => perms.some((p) => p.code === l.perm));
  view().innerHTML = `<div class="page-head"><div><div class="eyebrow">Διαχείριση</div><h1>Ρόλοι & Δικαιώματα · Ταμεία</h1>
    <p class="muted">Ποιος ρόλος κάνει τι στα Ταμεία. Ο πίνακας είναι ο ίδιος με της εφαρμογής Μισθοδοσίας / HR (ενότητα «Ταμεία») και τον εφαρμόζει η βάση σε κάθε ενέργεια.
    Η ρεσεψιόν δεν χρειάζεται λογαριασμό· υποβάλλει από τον σύνδεσμο του καταστήματος.</p></div></div>
  <div class="card"><div class="table-wrap"><table class="perm-table"><thead><tr><th>Ενέργεια</th>${ROLES.map((r) => `<th class="c">${ROLE_GR[r]}</th>`).join("")}</tr>
    <tr class="scope-row"><th>Πεδίο καταστημάτων <span class="sub">(κοινό με την εφαρμογή HR)</span></th>${ROLES.map((r) => `<th class="c small" style="text-transform:none;font-weight:600">${SCOPE_GR[M.scopes[r]]}</th>`).join("")}</tr></thead>
    <tbody>${perms.map((p) => `<tr><td>${h(p.label)}${p.description ? `<span class="sub">${h(p.description)}</span>` : ""}</td>
      ${ROLES.map((r) => `<td class="c"><input type="checkbox" data-r="${r}" data-p="${p.code}" ${draft[r][p.code] ? "checked" : ""} ${locked(r, p) ? "disabled" : ""} aria-label="${h(ROLE_GR[r])}: ${h(p.label)}" title="${locked(r, p) ? "Σταθερό — δεν αλλάζει από τον πίνακα" : ""}"></td>`).join("")}</tr>`).join("")}</tbody></table></div>
    <p class="muted small" style="margin-top:8px">Η έγκριση διορθώσεων κλειδωμένων στοιχείων ανήκει μόνο στη Γενική Διεύθυνση. Το πεδίο καταστημάτων ανά ρόλο αλλάζει από την εφαρμογή HR → Ρόλοι & Δικαιώματα.</p>
    <div class="row-actions" style="margin-top:12px"><input id="pm-note" placeholder="Αιτιολογία αλλαγής (υποχρεωτική)" maxlength="300" style="flex:1;min-width:220px"><span class="muted small" id="pm-n"></span><button class="btn primary" id="pm-save" disabled>Αποθήκευση αλλαγών</button></div></div>
  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Ιστορικό αλλαγών</h3></div>
    ${logs.length ? `<div class="table-wrap" style="max-height:340px"><table><thead><tr><th>Πότε</th><th>Ποιος</th><th>Ρόλος</th><th>Δικαίωμα</th><th>Αλλαγή</th><th>Αιτιολογία</th></tr></thead><tbody>
      ${logs.map((l) => `<tr><td class="small">${athensTime(l.at)}</td><td class="small">${h(l.actor)}</td><td>${ROLE_GR[l.role] || h(l.role)}</td><td class="small">${h(perms.find((p) => p.code === l.perm)?.label || l.perm)}</td>
        <td class="small">${l.old_value === "true" ? "Ναι" : "Όχι"} → <strong>${l.new_value === "true" ? "Ναι" : "Όχι"}</strong></td><td class="small">${h(l.note || "")}</td></tr>`).join("")}</tbody></table></div>`
    : `<p class="muted">Καμία αλλαγή ακόμη. Ισχύουν οι αρχικές ρυθμίσεις: έγκριση επιστροφών μόνο η Γενική Διευθύντρια.</p>`}</div>`;
  const upd = () => { const n = changes().length; $("#pm-n").textContent = n ? `${n} αλλαγές` : ""; $("#pm-save").disabled = !n; };
  $$("[data-r]").forEach((c) => (c.onchange = () => { draft[c.dataset.r][c.dataset.p] = c.checked; c.closest("td").classList.toggle("chg", c.checked !== M.grants[c.dataset.r][c.dataset.p]); upd(); }));
  $("#pm-save").onclick = act(async () => {
    const r = await S.rpc("permissions_save", { p_changes: changes(), p_scopes: {}, p_note: $("#pm-note").value.trim() });
    toast(`Αποθηκεύτηκαν ${r.changed} αλλαγές. Ισχύουν από την επόμενη ενέργεια κάθε χρήστη.`);
    S.me = await S.rpc("whoami"); S.lists = await S.rpc("cash_lists").catch(() => S.lists);
  });
}

// ═══════════════ Ρυθμίσεις ═══════════════
async function settingsView() {
  S.lists = await S.rpc("cash_lists");
  const C = S.lists.categories;
  view().innerHTML = `<div class="page-head"><div><div class="eyebrow">Διαχείριση</div><h1>Ρυθμίσεις ταμείων</h1></div></div>
  <div class="card"><div class="card-head"><h3>Κατηγορίες εξόδων</h3><button class="btn sm primary" id="ct-add">+ Νέα κατηγορία</button></div>
    <div class="table-wrap"><table><thead><tr><th>Κατηγορία</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
    ${C.map((c) => `<tr><td><strong>${h(c.name)}</strong></td><td>${c.active ? `<span class="badge b-signed">Ενεργή</span>` : `<span class="badge b-missing">Ανενεργή</span>`}</td>
      <td class="acts"><div class="row-actions"><button class="btn sm" data-ren="${h(c.name)}">Μετονομασία</button><button class="btn sm" data-tog="${h(c.name)}" data-act="${c.active ? 0 : 1}">${c.active ? "Απενεργοποίηση" : "Ενεργοποίηση"}</button></div></td></tr>`).join("")}
    </tbody></table></div>
    <p class="muted small" style="margin-top:8px">Οι ανενεργές κατηγορίες δεν εμφανίζονται σε νέα έξοδα· τα παλιά έξοδα τις κρατούν.</p></div>
  <div class="card"><div class="card-head"><h3>Ταμείο έναρξης</h3></div><p>Σταθερά <strong>100,00 €</strong> για ρέστα σε κάθε κατάστημα. Δεν περιλαμβάνεται στις εισπράξεις ούτε στο ποσό προς κατάθεση.</p></div>`;
  $("#ct-add").onclick = async () => { const n = await confirmBox("Νέα κατηγορία εξόδων", "", { ok: "Προσθήκη", input: "Όνομα" }); if (n) act(() => S.rpc("cash_category_save", { p_name: null, p_new_name: n, p_active: true, p_sort: null }), "Προστέθηκε.")(); };
  $$("[data-ren]").forEach((b) => (b.onclick = async () => { const n = await confirmBox("Μετονομασία", `Νέο όνομα για «${b.dataset.ren}»`, { ok: "Αποθήκευση", input: "Όνομα" }); if (n) act(() => S.rpc("cash_category_save", { p_name: b.dataset.ren, p_new_name: n, p_active: null, p_sort: null }), "Αποθηκεύτηκε.")(); }));
  $$("[data-tog]").forEach((b) => (b.onclick = act(() => S.rpc("cash_category_save", { p_name: b.dataset.tog, p_new_name: null, p_active: b.dataset.act === "1", p_sort: null }), "Αποθηκεύτηκε.")));
}

function account() {
  view().innerHTML = `<div class="page-head"><div><div class="eyebrow">Λογαριασμός</div><h1>${h(S.me.name)}</h1><p class="muted">${h(S.me.email)} · ${ROLE_GR[S.me.role]}${S.me.store ? " · " + h(S.me.store) : ""}</p></div></div>
  <div class="card"><p>Ο λογαριασμός είναι κοινός με την εφαρμογή Μισθοδοσίας / HR. Κωδικούς και χρήστες διαχειρίζεται η Γενική Διευθύντρια από εκεί.</p>
    <div class="row-actions" style="margin-top:14px"><a class="btn" href="../">↗ Μισθοδοσία / HR</a><button class="btn danger" id="ac-out">Αποσύνδεση</button></div></div>`;
  $("#ac-out").onclick = async () => { await S.signOut(); location.hash = ""; location.reload(); };
}

// ═══════════════ Εκκίνηση ═══════════════
function drawMe() { $("#me-box").innerHTML = `<strong>${h(S.me.name)}</strong><span>${h(S.me.email)}</span><br><span class="role-chip">${ROLE_GR[S.me.role] || ""}${S.me.store ? " · " + h(S.me.store) : ""}</span>`; }
const hasAccess = (me) => me?.role && (me.perms || []).some((p) => p.startsWith("cash.") || p === "permissions.manage");
async function showApp() {
  S.lists = P("cash.view") ? await S.rpc("cash_lists") : { stores: [], categories: [], approvers: [], today: isoDate(new Date()) };
  $("#login").hidden = true; $("#boot").hidden = true; $("#app").hidden = false;
  drawMe(); route();
}
function showLogin(msg) { $("#boot").hidden = true; $("#app").hidden = true; $("#login").hidden = false; if (msg) $("#login-msg").textContent = msg; $("#login-email").focus(); }

async function boot() {
  const cfg = window.MEGA_CONFIG || {};
  let api = window.__TAMEIA_MOCK;
  if (!api) {
    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) { $("#boot").innerHTML = `<div style="color:#fff;text-align:center;padding:20px">Η εφαρμογή Ταμεία χρειάζεται σύνδεση με τη βάση.<br><small>Ρυθμίζεται αυτόματα με το deploy.</small></div>`; return; }
    await loadScript("../vendor/supabase.js");
    // Ίδιο κλειδί συνεδρίας με την εφαρμογή HR: όποιος είναι συνδεδεμένος εκεί, μπαίνει κατευθείαν εδώ
    const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: true, autoRefreshToken: true, storageKey: "mega-payroll-auth" } });
    api = {
      rpc: async (n, a) => { const { data, error } = await sb.rpc(n, a); if (error) throw new Error(friendly(error)); return data; },
      session: async () => (await sb.auth.getSession()).data.session,
      signIn: async (e, p) => { const { error } = await sb.auth.signInWithPassword({ email: e.trim().toLowerCase(), password: p }); if (error) throw new Error(friendly(error)); },
      signOut: () => sb.auth.signOut(),
      onSignedOut: (cb) => sb.auth.onAuthStateChange((ev) => { if (ev === "SIGNED_OUT") cb(); }),
    };
  }
  S.rpc = api.rpc; S.signOut = api.signOut;
  api.onSignedOut?.(() => { if (S.me) location.reload(); });
  $("#login-form").onsubmit = async (e) => {
    e.preventDefault(); const btn = $("#login-form button"); btn.disabled = true; $("#login-msg").textContent = "";
    try {
      await api.signIn($("#login-email").value, $("#login-password").value);
      const me = await S.rpc("whoami");
      if (!hasAccess(me)) { await api.signOut(); throw new Error("Ο λογαριασμός δεν έχει πρόσβαση στα Ταμεία. Επικοινωνήστε με τη Γενική Διευθύντρια."); }
      S.me = me; await showApp();
    } catch (err) { $("#login-msg").textContent = friendly(err); }
    btn.disabled = false;
  };
  // Νυχτερινή εμφάνιση: προτίμηση αυτού του browser
  const theme = () => document.documentElement.dataset.theme === "dark";
  const drawTheme = () => { const b = $("#theme-btn"); b.textContent = theme() ? "☀ Ημέρα" : "🌙 Νύχτα"; b.setAttribute("aria-pressed", String(theme())); b.title = theme() ? "Φωτεινή εμφάνιση" : "Νυχτερινή εμφάνιση"; };
  $("#theme-btn").onclick = () => {
    if (theme()) delete document.documentElement.dataset.theme; else document.documentElement.dataset.theme = "dark";
    try { localStorage.setItem("mg-tameia-theme", theme() ? "dark" : "light"); } catch {}
    drawTheme();
  };
  drawTheme();
  $("#open-menu").onclick = () => $("#app").classList.add("menu-open");
  $("#close-menu").onclick = $("#scrim").onclick = () => $("#app").classList.remove("menu-open");
  window.addEventListener("hashchange", route);
  try {
    if (await api.session()) {
      const me = await S.rpc("whoami");
      if (hasAccess(me)) { S.me = me; return await showApp(); }
      return showLogin(me?.role ? "Ο λογαριασμός δεν έχει πρόσβαση στα Ταμεία." : "");
    }
    showLogin("");
  } catch (e) { showLogin(friendly(e)); }
}
boot();
