// Οθόνες: Επισκόπηση, Εκκρεμότητες, Προετοιμασία, Δηλώσεις, Εργαζόμενοι
import { S, can, role, getStatus, getEmployees, invalidate, visibleStores, activeStores, activeCompanies } from "./core.js";
import {
  $, $$, h, badge, money, monthLabel, shiftMonth, monthBounds, defaultPeriod, dmy, dateTime, relTime, parseAmount,
  statementText, amountText, toast, openDialog, closeDialog, confirmBox, downloadXlsx, readXlsx, norm, initials, STATUS,
} from "./util.js";
import { signaturePad } from "./signature.js";
import { downloadDeclarationPdf } from "./pdf.js";

const view = () => $("#view");
export const rerender = () => window.dispatchEvent(new Event("mg:rerender"));

function storeSelect(id, value, { all = true } = {}) {
  if (role() === "manager") return "";
  return `<select id="${id}">${all ? `<option value="">Όλα τα καταστήματα</option>` : ""}${visibleStores().map((s) => `<option ${s === value ? "selected" : ""}>${h(s)}</option>`).join("")}</select>`;
}
const count = (rows, st) => rows.filter((r) => r.status === st).length;
const greeting = () => { const hr = new Date().getHours(); return hr < 12 ? "Καλημέρα" : hr < 18 ? "Καλησπέρα" : "Καλησπέρα"; };

// ═══════════════════════ Επισκόπηση ═══════════════════════
export async function overview() {
  const rows = await getStatus();
  const prevRows = await getStatus(shiftMonth(S.month, -1)).catch(() => []);
  const total = rows.filter((r) => r.emp_status === "Ενεργός" || r.status !== "missing").length;
  const signed = count(rows, "signed"), pending = count(rows, "pending"), missing = count(rows, "missing");
  const pct = total ? Math.round((signed / total) * 100) : 0;
  const prevSigned = count(prevRows, "signed"), prevTotal = prevRows.length;
  const sum = (st) => rows.filter((r) => r.status === st).reduce((a, r) => a + Number(r.amount || 0), 0);

  const stores = {};
  for (const r of rows) {
    const s = (stores[r.store] ??= { name: r.store, total: 0, signed: 0, pending: 0, missing: 0 });
    s.total++; s[r.status]++;
  }
  const companies = {};
  for (const r of rows.filter((r) => r.status !== "missing")) {
    const c = (companies[r.company] ??= { name: r.company, n: 0, amount: 0, signed: 0 });
    c.n++; c.amount += Number(r.amount || 0); if (r.status === "signed") c.signed++;
  }
  const recent = rows.filter((r) => r.signed_at).sort((a, b) => (a.signed_at < b.signed_at ? 1 : -1)).slice(0, 8);

  view().innerHTML = `
  <div class="page-head">
    <div><div class="eyebrow">${h(monthLabel(S.month))}</div><h1>${greeting()}, ${h(S.me.name.split(" ")[0])}</h1>
    <p class="muted">${role() === "manager" ? `Κατάστημα ${h(S.me.store)}` : "Όλα τα καταστήματα"} · ${pct}% των δηλώσεων του μήνα έχουν υπογραφεί.</p></div>
    <div class="row-actions">
      ${can.prepare() ? `<a class="btn" href="#/prepare">✎ Προετοιμασία δηλώσεων</a>` : ""}
      ${can.sign() ? `<a class="btn primary" href="#/tablet">▣ Tablet καταστήματος</a>` : ""}
    </div>
  </div>
  <div class="grid g4">
    <a class="card kpi" href="#/pending" style="text-decoration:none"><div class="label">Ενεργοί εργαζόμενοι</div><div class="value num">${total}</div><div class="hint">με υποχρέωση δήλωσης</div></a>
    <a class="card kpi ok" href="#/declarations" style="text-decoration:none"><div class="label">Υπογεγραμμένες</div><div class="value num">${signed}</div><div class="hint">${pct}% · προηγ. μήνας ${prevSigned}/${prevTotal}</div></a>
    <a class="card kpi warn" href="#/pending?f=pending" style="text-decoration:none"><div class="label">Προς υπογραφή</div><div class="value num">${pending}</div><div class="hint">έτοιμες, περιμένουν τον εργαζόμενο</div></a>
    <a class="card kpi bad" href="#/pending?f=missing" style="text-decoration:none"><div class="label">Χωρίς δήλωση</div><div class="value num">${missing}</div><div class="hint">δεν έχουν ετοιμαστεί ακόμη</div></a>
  </div>
  <div class="card" style="margin-top:16px">
    <div class="card-head"><h3>Πρόοδος ανά κατάστημα</h3>
      <div class="legend"><span><i style="background:var(--ok)"></i>Υπογεγραμμένες</span><span><i style="background:#f0b23a"></i>Προς υπογραφή</span><span><i style="background:#eef0f3;border:1px solid #d5dae0"></i>Χωρίς δήλωση</span></div></div>
    ${Object.values(stores).length ? Object.values(stores).map((s) => `
      <a class="store-row" href="#/pending?store=${encodeURIComponent(s.name)}" style="text-decoration:none">
        <div class="name">${h(s.name)}</div>
        <div class="bar" title="${s.signed} υπογεγραμμένες · ${s.pending} προς υπογραφή · ${s.missing} χωρίς δήλωση">
          <span class="s" style="width:${(s.signed / s.total) * 100}%"></span><span class="p" style="width:${(s.pending / s.total) * 100}%"></span></div>
        <div class="num r small" style="text-align:right"><strong>${s.signed}</strong>/${s.total} ${s.signed === s.total ? "✓" : ""}</div>
      </a>`).join("") : `<div class="empty">Δεν υπάρχουν ενεργοί εργαζόμενοι.${can.editEmployees() ? ` <a href="#/employees">Προσθήκη εργαζομένων</a>` : ""}</div>`}
  </div>
  <div class="grid g2" style="margin-top:16px">
    <div class="card"><div class="card-head"><h3>Πρόσφατες υπογραφές</h3><a class="btn sm ghost" href="#/declarations">Όλες →</a></div>
      ${recent.length ? recent.map((r) => `<div class="list-item"><div class="avatar">${h(initials(r.first + " " + r.last))}</div>
        <div class="grow"><strong>${h(r.first)} ${h(r.last)}</strong><div class="muted small">${h(r.store)} · ${money(r.amount)}</div></div>
        <span class="muted small">${relTime(r.signed_at)}</span></div>`).join("") : `<div class="empty"><div class="big">✍︎</div>Καμία υπογραφή ακόμη για ${h(monthLabel(S.month))}.</div>`}
    </div>
    <div class="card"><div class="card-head"><h3>Ποσά μήνα</h3></div>
      <div class="grid g2" style="gap:10px">
        <div><div class="muted small">Υπογεγραμμένα</div><div style="font-size:22px;font-weight:800" class="num">${money(sum("signed"))}</div></div>
        <div><div class="muted small">Προς υπογραφή</div><div style="font-size:22px;font-weight:800" class="num">${money(sum("pending"))}</div></div>
      </div>
      <div class="table-wrap" style="margin-top:14px"><table><thead><tr><th>Εταιρεία</th><th class="r">Δηλώσεις</th><th class="r">Ποσό</th></tr></thead><tbody>
      ${Object.values(companies).map((c) => `<tr><td>${h(c.name)}</td><td class="r num">${c.signed}/${c.n}</td><td class="r num">${money(c.amount)}</td></tr>`).join("") || `<tr><td colspan="3" class="muted">Δεν υπάρχουν δηλώσεις για τον μήνα.</td></tr>`}
      </tbody></table></div>
    </div>
  </div>`;
}

// ═══════════════════════ Εκκρεμότητες ═══════════════════════
export async function pending(params) {
  const F = (S.filters.pending ??= { status: "open", store: "", q: "" });
  if (params.get("f")) F.status = params.get("f");
  if (params.get("store") !== null) F.store = params.get("store") || "";
  const rows = await getStatus();
  const match = (r) =>
    (!F.store || r.store === F.store) &&
    (F.status === "all" || (F.status === "open" ? r.status !== "signed" : r.status === F.status)) &&
    (!F.q || norm(`${r.first} ${r.last} ${r.code}`).includes(norm(F.q)));
  const base = rows.filter((r) => !F.store || r.store === F.store);
  const list = rows.filter(match);
  const chip = (k, label, n) => `<button class="chip ${F.status === k ? "on" : ""}" data-f="${k}">${label}<span class="n">${n}</span></button>`;

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(monthLabel(S.month))}</div><h1>Εκκρεμότητες μήνα</h1>
    <p class="muted">Ποιος έχει υπογράψει, ποιος περιμένει και για ποιον δεν έχει ετοιμαστεί δήλωση.</p></div>
    <div class="row-actions">
      <button class="btn" id="pend-export">⇩ Excel</button>
      ${can.prepare() && count(base, "missing") ? `<a class="btn" href="#/prepare">✎ Ετοιμασία για ${count(base, "missing")} χωρίς δήλωση</a>` : ""}
      ${can.sign() && count(base, "pending") ? `<a class="btn primary" href="#/tablet">▣ Υπογραφές στο tablet</a>` : ""}
    </div></div>
  <div class="card">
    <div class="toolbar">
      <input type="search" id="pend-q" placeholder="Αναζήτηση ονόματος ή κωδικού" value="${h(F.q)}">
      ${storeSelect("pend-store", F.store)}
      <div class="chips">
        ${chip("open", "Εκκρεμείς", base.filter((r) => r.status !== "signed").length)}
        ${chip("missing", "Χωρίς δήλωση", count(base, "missing"))}
        ${chip("pending", "Προς υπογραφή", count(base, "pending"))}
        ${chip("signed", "Υπογεγραμμένες", count(base, "signed"))}
        ${chip("all", "Όλοι", base.length)}
      </div>
    </div>
    ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα</th><th class="hide-sm">Εταιρεία</th><th class="r">Ποσό</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${list.map((r) => `<tr>
        <td><strong>${h(r.first)} ${h(r.last)}</strong><span class="sub">${h(r.code)}</span></td>
        <td data-l="Κατάστημα">${h(r.store)}</td><td class="hide-sm">${h(r.company)}</td>
        <td class="r num" data-l="Ποσό">${r.amount != null ? money(r.amount) : "—"}</td>
        <td>${badge(r.status)}${r.signed_at ? `<span class="sub">${dateTime(r.signed_at)}</span>` : ""}</td>
        <td class="acts"><div class="row-actions" style="justify-content:flex-end">
          ${r.status === "missing" && can.prepare() ? `<button class="btn sm" data-prep="${h(r.code)}">Ετοιμασία</button>` : ""}
          ${r.status === "pending" && can.prepare() ? `<button class="btn sm ghost" data-prep="${h(r.code)}">Αλλαγή</button>` : ""}
          ${r.status === "pending" && can.sign() ? `<button class="btn sm primary" data-sign="${h(r.code)}">Υπογραφή</button>` : ""}
          ${r.status === "signed" ? `<button class="btn sm" data-view="${h(r.declaration_id)}">Προβολή</button>` : ""}
        </div></td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty"><div class="big">✓</div>${F.status === "open" ? "Καμία εκκρεμότητα! Όλοι έχουν υπογράψει." : "Δεν βρέθηκαν εργαζόμενοι με αυτά τα φίλτρα."}</div>`}
  </div>`;

  $("#pend-q").oninput = (e) => { F.q = e.target.value; const pos = e.target.selectionStart; pending(new URLSearchParams()).then(() => { const i = $("#pend-q"); i.focus(); i.setSelectionRange(pos, pos); }); };
  $("#pend-store") && ($("#pend-store").onchange = (e) => { F.store = e.target.value; pending(new URLSearchParams()); });
  $$("[data-f]").forEach((b) => (b.onclick = () => { F.status = b.dataset.f; pending(new URLSearchParams()); }));
  $$("[data-prep]").forEach((b) => (b.onclick = () => prepareOne(rows.find((r) => r.code === b.dataset.prep))));
  $$("[data-sign]").forEach((b) => (b.onclick = () => signDialog(rows.find((r) => r.code === b.dataset.sign))));
  $$("[data-view]").forEach((b) => (b.onclick = () => viewDeclaration(b.dataset.view)));
  $("#pend-export").onclick = () => downloadXlsx(`Εκκρεμότητες_${S.month}.xlsx`, {
    [monthLabel(S.month)]: [["Κωδικός", "Επώνυμο", "Όνομα", "Κατάστημα", "Εταιρεία", "Κατάσταση", "Ποσό", "Υπογραφή"],
      ...list.map((r) => [r.code, r.last, r.first, r.store, r.company, STATUS[r.status].label, r.amount != null ? Number(r.amount) : "", r.signed_at ? dateTime(r.signed_at) : ""])],
  });
}

// Μία δήλωση (ετοιμασία ή αλλαγή)
export function prepareOne(r) {
  const b = monthBounds(S.month);
  openDialog(`
    <div class="dlg-head"><div><div class="eyebrow">${h(monthLabel(S.month))}</div><h2>${r.status === "pending" ? "Αλλαγή" : "Ετοιμασία"} δήλωσης</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p><strong>${h(r.first)} ${h(r.last)}</strong> <span class="muted">· ${h(r.code)} · ${h(r.store)} · ${h(r.company)}</span></p>
    <form id="p1"><div class="grid g3">
      <div><label>Ποσό τραπεζικής κατάθεσης (€)</label><input id="p1-amount" inputmode="decimal" required placeholder="π.χ. 1.000,00" value="${r.amount != null ? h(amountText(r.amount)) : ""}"></div>
      <div><label>Χρονικό διάστημα</label><input id="p1-period" required maxlength="120" value="${h(r.period || defaultPeriod(S.month))}"></div>
      <div><label>Έως την ημερομηνία</label><input id="p1-end" type="date" required value="${h(String(r.end_date || b.last).slice(0, 10))}"></div>
    </div>
    <p id="p1-msg" class="form-msg"></p>
    <div class="dlg-foot"><button type="button" class="btn" data-close>Άκυρο</button>
      ${r.status === "pending" ? `<button type="button" class="btn danger" id="p1-discard">Αφαίρεση</button>` : ""}
      <button class="btn primary">${r.status === "pending" ? "Αποθήκευση" : "Ετοιμασία για υπογραφή"}</button></div></form>`,
    {
      onOpen() {
        $("#p1-amount").focus();
        $("#p1").onsubmit = async (e) => {
          e.preventDefault();
          const amount = parseAmount($("#p1-amount").value);
          if (amount === null) return ($("#p1-msg").textContent = "Μη έγκυρο ποσό.");
          try {
            const res = await S.api.prepare(S.month, [{ code: r.code, amount: String(amount), period: $("#p1-period").value, end_date: $("#p1-end").value }]);
            if (res.skipped?.length) return ($("#p1-msg").textContent = res.skipped[0].reason);
            closeDialog(); invalidate(); toast("Η δήλωση είναι έτοιμη για υπογραφή."); rerender();
          } catch (err) { $("#p1-msg").textContent = err.message; }
        };
        $("#p1-discard") && ($("#p1-discard").onclick = async () => {
          try { await S.api.discardPending(r.declaration_id); closeDialog(); invalidate(); toast("Η δήλωση αφαιρέθηκε."); rerender(); }
          catch (err) { $("#p1-msg").textContent = err.message; }
        });
      },
    }
  );
}

// Υπογραφή σε παράθυρο (από υπολογιστή/κινητό)
export function signDialog(r, { onDone } = {}) {
  let pad;
  openDialog(`
    <div class="dlg-head"><div><div class="eyebrow">${h(monthLabel(S.month))} · ${h(r.store)}</div><h2>Δήλωση εργαζομένου</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p><strong>${h(r.first)} ${h(r.last)}</strong> <span class="muted">· ${h(r.code)}</span></p>
    <div class="statement">${h(statementText(r.company, r.end_date, r.period, r.amount))}</div>
    <label for="sg-name">Ονοματεπώνυμο εργαζομένου</label><input id="sg-name" maxlength="150" autocomplete="off" placeholder="Γράψτε το ονοματεπώνυμό σας">
    <label>Υπογραφή</label><div class="sig-wrap" id="sg-pad"></div>
    <p id="sg-msg" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" id="sg-clear">Καθαρισμός</button><span class="spacer"></span><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="sg-ok">Υποβολή δήλωσης</button></div>`,
    {
      wide: true,
      onOpen(d) {
        pad = signaturePad($("#sg-pad"));
        d.addEventListener("close", () => pad.destroy(), { once: true });
        $("#sg-clear").onclick = () => pad.clear();
        $("#sg-ok").onclick = async () => {
          const name = $("#sg-name").value.trim();
          if (name.length < 3) return ($("#sg-msg").textContent = "Συμπληρώστε το ονοματεπώνυμο.");
          if (pad.isEmpty()) return ($("#sg-msg").textContent = "Η υπογραφή λείπει.");
          const btn = $("#sg-ok"); btn.disabled = true; btn.textContent = "Αποθήκευση…";
          try {
            await S.api.sign(r.declaration_id, name, pad.toPng());
            closeDialog(); invalidate(); toast(`Η δήλωση του/της ${r.first} ${r.last} υπογράφηκε.`);
            onDone ? onDone() : rerender();
          } catch (err) { $("#sg-msg").textContent = err.message; btn.disabled = false; btn.textContent = "Υποβολή δήλωσης"; }
        };
      },
    }
  );
}

// Προβολή δήλωσης
export async function viewDeclaration(id) {
  openDialog(`<div class="empty"><div class="spinner"></div></div>`);
  let d;
  try { d = await S.api.declaration(id); } catch (e) { closeDialog(); return toast(e.message, true); }
  openDialog(`
    <div class="dlg-head"><div><div class="eyebrow">${h(monthLabel(d.month))}</div><h2>${h(d.employee_name)}</h2></div><button class="icon-btn" data-close>✕</button></div>
    ${badge(d.status)}
    <dl class="kv">
      <dt>Κωδικός</dt><dd>${h(d.employee_code)}</dd>
      <dt>Κατάστημα</dt><dd>${h(d.store)}</dd>
      <dt>Εταιρεία</dt><dd>${h(d.company)}</dd>
      <dt>Διάστημα</dt><dd>${h(d.period)} · έως ${dmy(d.end_date)}</dd>
      <dt>Ποσό</dt><dd>${money(d.amount)}</dd>
      ${d.signed_at ? `<dt>Υπογραφή</dt><dd>${dateTime(d.signed_at)}${d.signed_by ? ` · συσκευή του ${h(d.signed_by)}` : ""}</dd>` : ""}
      <dt>Προετοιμασία</dt><dd>${dateTime(d.prepared_at)}${d.prepared_by ? ` · ${h(d.prepared_by)}` : ""}</dd>
      ${d.status === "voided" ? `<dt>Ακύρωση</dt><dd>${dateTime(d.voided_at)} · ${h(d.voided_by)} — «${h(d.void_reason)}»</dd>` : ""}
    </dl>
    <div class="statement">${h(d.statement || statementText(d.company, d.end_date, d.period, d.amount))}</div>
    ${d.signature ? `<p style="margin-top:14px"><img class="sig-img" src="${h(d.signature)}" alt="Υπογραφή"></p><p><strong>${h(d.signer)}</strong></p>` : ""}
    <div class="dlg-foot">
      ${can.void() && d.status !== "voided" ? `<button class="btn danger" id="vd-void">Ακύρωση δήλωσης</button>` : ""}
      <span class="spacer"></span>
      ${d.status === "signed" ? `<button class="btn" id="vd-pdf">⇩ PDF</button>` : ""}
      <button class="btn primary" data-close>Κλείσιμο</button></div>`,
    {
      wide: true,
      onOpen() {
        $("#vd-pdf") && ($("#vd-pdf").onclick = async () => { try { await downloadDeclarationPdf(d); } catch (e) { toast("Δεν δημιουργήθηκε το PDF: " + e.message, true); } });
        $("#vd-void") && ($("#vd-void").onclick = async () => {
          const reason = await confirmBox("Ακύρωση δήλωσης", "Η δήλωση θα μείνει στο αρχείο ως ακυρωμένη και θα μπορεί να γίνει νέα για τον ίδιο μήνα.", { ok: "Ακύρωση δήλωσης", danger: true, input: "Αιτιολογία" });
          if (!reason) return;
          try { await S.api.voidDeclaration(d.id, reason); invalidate(); toast("Η δήλωση ακυρώθηκε."); rerender(); } catch (e) { toast(e.message, true); }
        });
      },
    }
  );
}

// ═══════════════════════ Προετοιμασία (μαζική) ═══════════════════════
export async function prepare() {
  const F = (S.filters.prepare ??= { tab: "screen", store: "", q: "" });
  const rows = await getStatus();
  const todo = rows.filter((r) => r.status !== "signed" && r.emp_status === "Ενεργός");
  const b = monthBounds(S.month);
  const per = (S.filters.prepDefaults ??= {});
  if (per.month !== S.month) Object.assign(per, { month: S.month, period: defaultPeriod(S.month), end: b.last });

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(monthLabel(S.month))}</div><h1>Προετοιμασία δηλώσεων</h1>
    <p class="muted">Συμπληρώστε τα ποσά μία φορά. Μετά ο manager απλώς δίνει το tablet στον εργαζόμενο να υπογράψει.</p></div></div>
  <div class="card">
    <div class="grid g3">
      <div><label>Χρονικό διάστημα (για όλους)</label><input id="pr-period" maxlength="120" value="${h(per.period)}"></div>
      <div><label>Έως την ημερομηνία</label><input id="pr-end" type="date" value="${h(per.end)}"></div>
      <div><label>Τρόπος</label><div class="chips" style="margin-top:4px">
        <button class="chip ${F.tab === "screen" ? "on" : ""}" data-tab="screen">Στην οθόνη</button>
        <button class="chip ${F.tab === "excel" ? "on" : ""}" data-tab="excel">Από Excel</button></div></div>
    </div>
  </div>
  <div class="card" id="pr-body"></div>`;

  $("#pr-period").oninput = (e) => (per.period = e.target.value);
  $("#pr-end").onchange = (e) => (per.end = e.target.value);
  $$("[data-tab]").forEach((x) => (x.onclick = () => { F.tab = x.dataset.tab; prepare(); }));
  const body = $("#pr-body");

  const showResult = (res) => {
    invalidate();
    openDialog(`<div class="dlg-head"><h2>Ολοκληρώθηκε</h2><button class="icon-btn" data-close>✕</button></div>
      <p>Νέες δηλώσεις: <strong>${res.created}</strong> · Ενημερώθηκαν: <strong>${res.updated}</strong>${res.skipped.length ? ` · Παραλείφθηκαν: <strong>${res.skipped.length}</strong>` : ""}</p>
      ${res.skipped.length ? `<ul class="result-list">${res.skipped.slice(0, 50).map((s) => `<li>${h(s.code)}: ${h(s.reason)}</li>`).join("")}</ul>` : ""}
      <div class="dlg-foot"><button class="btn" data-close>Κλείσιμο</button>${can.sign() ? `<a class="btn primary" href="#/tablet" id="go-tab">▣ Άνοιγμα tablet υπογραφών</a>` : `<a class="btn primary" href="#/pending?f=pending" id="go-tab">Προβολή εκκρεμοτήτων</a>`}</div>`,
      { onOpen() { $("#go-tab").onclick = () => closeDialog(); } });
    prepare();
  };

  if (F.tab === "screen") {
    const list = todo.filter((r) => (!F.store || r.store === F.store) && (!F.q || norm(`${r.first} ${r.last} ${r.code}`).includes(norm(F.q))));
    body.innerHTML = `
      <div class="toolbar">
        <input type="search" id="pr-q" placeholder="Αναζήτηση" value="${h(F.q)}">
        ${storeSelect("pr-store", F.store)}
        <span class="spacer"></span>
        <span class="muted small" id="pr-count"></span>
        <button class="btn primary" id="pr-save">Αποθήκευση ποσών</button>
      </div>
      ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα</th><th class="hide-sm">Εταιρεία</th><th>Κατάσταση</th><th class="r">Ποσό (€)</th></tr></thead><tbody>
      ${list.map((r) => `<tr><td><strong>${h(r.first)} ${h(r.last)}</strong><span class="sub">${h(r.code)}</span></td><td data-l="Κατάστημα">${h(r.store)}</td><td class="hide-sm">${h(r.company)}</td><td>${badge(r.status)}</td>
        <td class="r"><input class="amount-in" inputmode="decimal" data-code="${h(r.code)}" data-orig="${r.amount ?? ""}" value="${r.amount != null ? h(amountText(r.amount)) : ""}" placeholder="0,00"></td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty"><div class="big">✓</div>Όλοι οι εργαζόμενοι έχουν υπογράψει για ${h(monthLabel(S.month))}.</div>`}`;
    const upd = () => {
      const ins = $$(".amount-in");
      const changed = ins.filter((i) => i.value.trim() && parseAmount(i.value) !== (i.dataset.orig === "" ? null : Number(i.dataset.orig)));
      const bad = ins.filter((i) => i.value.trim() && parseAmount(i.value) === null);
      ins.forEach((i) => (i.style.borderColor = i.value.trim() && parseAmount(i.value) === null ? "var(--bad)" : ""));
      $("#pr-count") && ($("#pr-count").textContent = `${changed.length} προς αποθήκευση${bad.length ? ` · ${bad.length} λάθος ποσά` : ""}`);
      return { changed, bad };
    };
    $$(".amount-in").forEach((i, idx, all) => {
      i.oninput = upd;
      i.onkeydown = (e) => { if (e.key === "Enter") { e.preventDefault(); all[idx + 1]?.focus(); } };
    });
    upd();
    $("#pr-q").oninput = (e) => { F.q = e.target.value; prepare().then(() => { const i = $("#pr-q"); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }); };
    $("#pr-store") && ($("#pr-store").onchange = (e) => { F.store = e.target.value; prepare(); });
    $("#pr-save").onclick = async () => {
      const { changed, bad } = upd();
      if (bad.length) return toast("Διορθώστε τα ποσά με κόκκινο.", true);
      if (!changed.length) return toast("Δεν υπάρχουν νέα ποσά για αποθήκευση.");
      const btn = $("#pr-save"); btn.disabled = true;
      try {
        showResult(await S.api.prepare(S.month, changed.map((i) => ({ code: i.dataset.code, amount: String(parseAmount(i.value)), period: per.period, end_date: per.end }))));
      } catch (e) { toast(e.message, true); btn.disabled = false; }
    };
  } else {
    body.innerHTML = `
      <h3>Από Excel</h3>
      <ol class="muted" style="line-height:1.9;padding-left:20px;margin:10px 0 16px">
        <li>Κατεβάστε το πρότυπο: έχει ήδη τους εργαζομένους που δεν έχουν υπογράψει για ${h(monthLabel(S.month))}.</li>
        <li>Συμπληρώστε τη στήλη «Ποσό». Αν χρειάζεται, αλλάξτε διάστημα/ημερομηνία ανά γραμμή.</li>
        <li>Ανεβάστε το αρχείο εδώ, ελέγξτε την προεπισκόπηση και πατήστε «Καταχώριση».</li></ol>
      <div class="row-actions"><button class="btn" id="pr-tpl">⇩ Πρότυπο Excel (${todo.length} εργαζόμενοι)</button>
        <label class="btn primary" style="margin:0">⇧ Ανέβασμα Excel<input type="file" id="pr-file" accept=".xlsx,.xls,.csv" hidden></label></div>
      <div id="pr-preview" style="margin-top:16px"></div>`;
    $("#pr-tpl").onclick = () => downloadXlsx(`Δηλώσεις_${S.month}.xlsx`, {
      "Δηλώσεις": [["Κωδικός εργαζομένου", "Ονοματεπώνυμο", "Κατάστημα", "Εταιρεία", "Ποσό (€)", "Χρονικό διάστημα", "Έως ημερομηνία"],
        ...todo.map((r) => [r.code, `${r.first} ${r.last}`, r.store, r.company, r.amount != null ? Number(r.amount) : "", per.period, dmy(per.end)])],
    });
    $("#pr-file").onchange = async (e) => {
      const file = e.target.files[0]; e.target.value = "";
      if (!file) return;
      try {
        const { wb, X } = await readXlsx(file);
        const ws = wb.Sheets["Δηλώσεις"] || wb.Sheets[wb.SheetNames[0]];
        const table = X.utils.sheet_to_json(ws, { header: 1, raw: true, defval: "" });
        const head = (table[0] || []).map((x) => norm(x));
        const col = (...names) => head.findIndex((x) => names.some((n) => x.includes(norm(n))));
        const ci = col("κωδικ"), ai = col("ποσ"), pi = col("διαστημα"), ei = col("εως");
        if (ci < 0 || ai < 0) throw new Error("Χρειάζονται τουλάχιστον οι στήλες «Κωδικός εργαζομένου» και «Ποσό».");
        const toIso = (v) => {
          if (v === "" || v == null) return "";
          if (typeof v === "number") { const d = X.SSF.parse_date_code(v); return `${d.y}-${String(d.m).padStart(2, "0")}-${String(d.d).padStart(2, "0")}`; }
          const s = String(v).trim(); let m;
          if ((m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/))) return `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
          if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
          return "bad";
        };
        const byCode = Object.fromEntries(rows.map((r) => [r.code, r]));
        const parsed = table.slice(1).filter((r) => String(r[ci] ?? "").trim()).map((r) => {
          const code = String(r[ci]).trim(), emp = byCode[code], amount = parseAmount(r[ai]);
          const end = ei >= 0 ? toIso(r[ei]) : "";
          let problem = "";
          if (!emp) problem = "Άγνωστος κωδικός ή άλλο κατάστημα";
          else if (emp.status === "signed") problem = "Έχει ήδη υπογράψει";
          else if (String(r[ai]).trim() === "") problem = "skip";
          else if (amount === null) problem = "Μη έγκυρο ποσό";
          else if (end === "bad") problem = "Μη έγκυρη ημερομηνία";
          return { code, emp, amount, period: pi >= 0 ? String(r[pi] || "").trim() : "", end_date: end && end !== "bad" ? end : "", problem };
        });
        const ok = parsed.filter((p) => !p.problem), errs = parsed.filter((p) => p.problem && p.problem !== "skip"), empty = parsed.filter((p) => p.problem === "skip");
        $("#pr-preview").innerHTML = `
          <div class="note ${errs.length ? "warn" : ""}">Βρέθηκαν <strong>${ok.length}</strong> έγκυρες γραμμές${errs.length ? `, <strong>${errs.length}</strong> με πρόβλημα` : ""}${empty.length ? ` και ${empty.length} χωρίς ποσό (θα αγνοηθούν)` : ""}.</div>
          <div class="table-wrap" style="margin-top:12px;max-height:420px"><table><thead><tr><th>Κωδικός</th><th>Εργαζόμενος</th><th class="r">Ποσό</th><th>Διάστημα</th><th>Έλεγχος</th></tr></thead><tbody>
          ${[...errs, ...ok].map((p) => `<tr><td>${h(p.code)}</td><td>${p.emp ? h(p.emp.first + " " + p.emp.last) : "—"}</td><td class="r num">${p.amount != null ? money(p.amount) : "—"}</td><td class="small">${h(p.period || per.period)}</td>
            <td>${p.problem ? `<span class="badge b-voided">${h(p.problem)}</span>` : `<span class="badge b-signed">OK</span>`}</td></tr>`).join("")}
          </tbody></table></div>
          <div class="row-actions" style="margin-top:14px"><button class="btn primary" id="pr-import" ${ok.length ? "" : "disabled"}>Καταχώριση ${ok.length} δηλώσεων</button></div>`;
        $("#pr-import").onclick = async () => {
          $("#pr-import").disabled = true;
          try {
            showResult(await S.api.prepare(S.month, ok.map((p) => ({ code: p.code, amount: String(p.amount), period: p.period || per.period, end_date: p.end_date || per.end }))));
          } catch (err) { toast(err.message, true); $("#pr-import").disabled = false; }
        };
      } catch (err) { toast(err.message, true); }
    };
  }
}

// ═══════════════════════ Δηλώσεις (αρχείο) ═══════════════════════
export async function declarations() {
  const F = (S.filters.decl ??= { allMonths: false, store: "", status: "signed", q: "" });
  const list0 = await S.api.declarations({ month: F.allMonths ? null : S.month, status: F.status || null, store: F.store || null });
  const list = list0.filter((d) => !F.q || norm(`${d.employee_name} ${d.employee_code} ${d.signer || ""}`).includes(norm(F.q)));
  const total = list.reduce((a, d) => a + Number(d.amount), 0);

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${F.allMonths ? "Όλοι οι μήνες" : h(monthLabel(S.month))}</div><h1>Δηλώσεις</h1>
    <p class="muted">Αρχείο δηλώσεων με υπογραφή, PDF και ιστορικό.</p></div>
    <div class="row-actions"><button class="btn" id="dc-export">⇩ Excel</button>${can.backup() ? `<a class="btn" href="#/backup">⇩ Backup PDF (ZIP)</a>` : ""}</div></div>
  <div class="card">
    <div class="toolbar">
      <input type="search" id="dc-q" placeholder="Αναζήτηση ονόματος ή κωδικού" value="${h(F.q)}">
      ${storeSelect("dc-store", F.store)}
      <select id="dc-status"><option value="signed">Υπογεγραμμένες</option><option value="pending">Προς υπογραφή</option><option value="voided">Ακυρωμένες</option><option value="">Όλες</option></select>
      <label class="chip ${F.allMonths ? "on" : ""}" style="margin:0"><input type="checkbox" id="dc-all" hidden ${F.allMonths ? "checked" : ""}>Όλοι οι μήνες</label>
      <span class="spacer"></span><span class="muted small">${list.length} δηλώσεις · ${money(total)}</span>
    </div>
    ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Μήνας</th><th>Κατάστημα</th><th class="r">Ποσό</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${list.slice(0, 1500).map((d) => `<tr><td><strong>${h(d.employee_name)}</strong><span class="sub">${h(d.employee_code)} · ${h(d.company)}</span></td>
        <td data-l="Μήνας">${h(monthLabel(d.month))}</td><td data-l="Κατάστημα">${h(d.store)}</td><td class="r num" data-l="Ποσό">${money(d.amount)}</td>
        <td>${badge(d.status)}${d.signed_at ? `<span class="sub">${dateTime(d.signed_at)}</span>` : ""}</td>
        <td class="acts" style="text-align:right"><button class="btn sm" data-view="${h(d.id)}">Προβολή</button></td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty"><div class="big">▤</div>Δεν υπάρχουν δηλώσεις με αυτά τα φίλτρα.</div>`}
  </div>`;
  $("#dc-status").value = F.status;
  $("#dc-q").oninput = (e) => { F.q = e.target.value; declarations().then(() => { const i = $("#dc-q"); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }); };
  $("#dc-store") && ($("#dc-store").onchange = (e) => { F.store = e.target.value; declarations(); });
  $("#dc-status").onchange = (e) => { F.status = e.target.value; declarations(); };
  $("#dc-all").onchange = (e) => { F.allMonths = e.target.checked; declarations(); };
  $$("[data-view]").forEach((b) => (b.onclick = () => viewDeclaration(b.dataset.view)));
  $("#dc-export").onclick = () => downloadXlsx(`Δηλώσεις_${F.allMonths ? "όλες" : S.month}.xlsx`, {
    "Δηλώσεις": [["Μήνας", "Κωδικός", "Εργαζόμενος", "Κατάστημα", "Εταιρεία", "Διάστημα", "Έως", "Ποσό", "Κατάσταση", "Υπογράφων", "Ημ/νία υπογραφής", "Αρ. δήλωσης"],
      ...list.map((d) => [d.month, d.employee_code, d.employee_name, d.store, d.company, d.period, dmy(d.end_date), Number(d.amount), STATUS[d.status].label, d.signer || "", d.signed_at ? dateTime(d.signed_at) : "", d.id])],
  });
}

// ═══════════════════════ Εργαζόμενοι ═══════════════════════
const EMP_HEAD = ["Κωδικός εργαζομένου", "Όνομα", "Επώνυμο", "Κατάστημα", "Εταιρεία", "Κατάσταση"];

export async function employees() {
  const F = (S.filters.emp ??= { q: "", store: "", status: "Ενεργός" });
  const all = await getEmployees();
  const list = all.filter((e) => (!F.store || e.store === F.store) && (!F.status || e.status === F.status) && (!F.q || norm(`${e.first} ${e.last} ${e.code}`).includes(norm(F.q))));
  const ed = can.editEmployees();

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Μητρώο προσωπικού</div><h1>Εργαζόμενοι</h1>
    <p class="muted">Κοινοί κωδικοί εργαζομένων για όλες τις εφαρμογές MEGA GYM.${role() === "manager" ? ` Βλέπετε το κατάστημα ${h(S.me.store)}.` : ""}</p></div>
    <div class="row-actions">
      <button class="btn" id="em-export">⇩ Excel</button>
      ${ed ? `<button class="btn" id="em-tpl">Πρότυπο</button><label class="btn" style="margin:0">⇧ Εισαγωγή Excel<input type="file" id="em-file" accept=".xlsx,.xls" hidden></label><button class="btn primary" id="em-new">+ Νέος εργαζόμενος</button>` : ""}
    </div></div>
  <div class="card">
    <div class="toolbar">
      <input type="search" id="em-q" placeholder="Αναζήτηση ονόματος ή κωδικού" value="${h(F.q)}">
      ${storeSelect("em-store", F.store)}
      <div class="chips">${[["Ενεργός", "Ενεργοί"], ["Ανενεργός", "Ανενεργοί"], ["", "Όλοι"]].map(([k, l]) => `<button class="chip ${F.status === k ? "on" : ""}" data-st="${k}">${l}<span class="n">${all.filter((e) => (!F.store || e.store === F.store) && (!k || e.status === k)).length}</span></button>`).join("")}</div>
    </div>
    ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα</th><th>Εταιρεία</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${list.map((e) => `<tr><td><strong>${h(e.last)} ${h(e.first)}</strong><span class="sub">${h(e.code)}</span></td><td data-l="Κατάστημα">${h(e.store)}</td><td data-l="Εταιρεία">${h(e.company)}</td>
        <td><span class="badge ${e.status === "Ενεργός" ? "b-signed" : "b-missing"}">${h(e.status)}</span></td>
        <td class="acts"><div class="row-actions" style="justify-content:flex-end"><button class="btn sm ghost" data-hist="${h(e.code)}">Ιστορικό</button>${ed ? `<button class="btn sm" data-edit="${h(e.code)}">Επεξεργασία</button>` : ""}</div></td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty"><div class="big">♙</div>${all.length ? "Δεν βρέθηκαν εργαζόμενοι με αυτά τα φίλτρα." : "Δεν υπάρχουν ακόμη εργαζόμενοι." + (ed ? " Προσθέστε έναν ή κάντε εισαγωγή από Excel." : "")}</div>`}
  </div>`;

  $("#em-q").oninput = (e) => { F.q = e.target.value; employees().then(() => { const i = $("#em-q"); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }); };
  $("#em-store") && ($("#em-store").onchange = (e) => { F.store = e.target.value; employees(); });
  $$("[data-st]").forEach((b) => (b.onclick = () => { F.status = b.dataset.st; employees(); }));
  $$("[data-edit]").forEach((b) => (b.onclick = () => employeeDialog(all.find((e) => e.code === b.dataset.edit))));
  $$("[data-hist]").forEach((b) => (b.onclick = () => employeeHistory(all.find((e) => e.code === b.dataset.hist))));
  $("#em-new") && ($("#em-new").onclick = () => employeeDialog(null));
  $("#em-export").onclick = () => downloadXlsx("Εργαζόμενοι.xlsx", { "Εργαζόμενοι": [EMP_HEAD, ...list.map((e) => [e.code, e.first, e.last, e.store, e.company, e.status])] });
  $("#em-tpl") && ($("#em-tpl").onclick = () => downloadXlsx("Πρότυπο_Εργαζομένων.xlsx", { "Εργαζόμενοι": [EMP_HEAD, ["MG1001", "Όνομα", "Επώνυμο", activeStores()[0], activeCompanies()[0], "Ενεργός"]], "Επιλογές": [["Καταστήματα", "Εταιρείες", "Κατάσταση"], ...Array.from({ length: Math.max(activeStores().length, activeCompanies().length) }, (_, i) => [activeStores()[i] || "", activeCompanies()[i] || "", ["Ενεργός", "Ανενεργός"][i] || ""])] }));
  $("#em-file") && ($("#em-file").onchange = (e) => { const f = e.target.files[0]; e.target.value = ""; if (f) importEmployees(f, all); });
}

function employeeDialog(e) {
  const isNew = !e;
  e ??= { code: "", first: "", last: "", store: S.filters.emp?.store || activeStores()[0], company: activeCompanies()[0], status: "Ενεργός" };
  const stores = [...new Set([...activeStores(), e.store])], comps = [...new Set([...activeCompanies(), e.company])];
  openDialog(`
    <div class="dlg-head"><h2>${isNew ? "Νέος εργαζόμενος" : "Επεξεργασία εργαζομένου"}</h2><button class="icon-btn" data-close>✕</button></div>
    <form id="ef"><div class="grid g2">
      <div><label>Κωδικός εργαζομένου</label><input id="ef-code" required maxlength="80" value="${h(e.code)}" ${isNew ? "" : "readonly"}></div>
      <div><label>Κατάσταση</label><select id="ef-status">${["Ενεργός", "Ανενεργός"].map((s) => `<option ${s === e.status ? "selected" : ""}>${s}</option>`).join("")}</select></div>
      <div><label>Όνομα</label><input id="ef-first" required maxlength="150" value="${h(e.first)}"></div>
      <div><label>Επώνυμο</label><input id="ef-last" required maxlength="150" value="${h(e.last)}"></div>
      <div><label>Κατάστημα</label><select id="ef-store">${stores.map((s) => `<option ${s === e.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select></div>
      <div><label>Εταιρεία</label><select id="ef-company">${comps.map((s) => `<option ${s === e.company ? "selected" : ""}>${h(s)}</option>`).join("")}</select></div>
    </div>
    ${isNew ? "" : `<p class="muted small" style="margin-top:10px">Ο κωδικός δεν αλλάζει, γιατί τον χρησιμοποιούν και οι άλλες εφαρμογές.</p>`}
    <p id="ef-msg" class="form-msg"></p>
    <div class="dlg-foot"><button type="button" class="btn" data-close>Άκυρο</button><button class="btn primary">Αποθήκευση</button></div></form>`,
    {
      onOpen() {
        (isNew ? $("#ef-code") : $("#ef-first")).focus();
        $("#ef").onsubmit = async (ev) => {
          ev.preventDefault();
          const v = { code: $("#ef-code").value.trim(), first: $("#ef-first").value.trim(), last: $("#ef-last").value.trim(), store: $("#ef-store").value, company: $("#ef-company").value, status: $("#ef-status").value };
          try { await S.api.saveEmployee(v, isNew); closeDialog(); invalidate(); toast("Αποθηκεύτηκε."); rerender(); }
          catch (err) { $("#ef-msg").textContent = err.message; }
        };
      },
    }
  );
}

async function employeeHistory(e) {
  const ds = (await S.api.declarations({})).filter((d) => d.employee_code === e.code);
  openDialog(`
    <div class="dlg-head"><div><div class="eyebrow">${h(e.code)} · ${h(e.store)}</div><h2>${h(e.first)} ${h(e.last)}</h2></div><button class="icon-btn" data-close>✕</button></div>
    ${ds.length ? `<div class="table-wrap" style="margin-top:10px"><table><thead><tr><th>Μήνας</th><th class="r">Ποσό</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
      ${ds.map((d) => `<tr><td>${h(monthLabel(d.month))}</td><td class="r num">${money(d.amount)}</td><td>${badge(d.status)}</td><td style="text-align:right"><button class="btn sm" data-view="${h(d.id)}">Προβολή</button></td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty">Δεν υπάρχουν δηλώσεις για αυτόν τον εργαζόμενο.</div>`}
    <div class="dlg-foot"><button class="btn primary" data-close>Κλείσιμο</button></div>`,
    { onOpen() { $$("#dlg [data-view]").forEach((b) => (b.onclick = () => viewDeclaration(b.dataset.view))); } });
}

async function importEmployees(file, existing) {
  try {
    const { sheet, wb } = await readXlsx(file);
    const table = sheet("Εργαζόμενοι") || sheet(wb.SheetNames[0]);
    if (!table) throw new Error("Δεν βρέθηκε το φύλλο «Εργαζόμενοι».");
    if (EMP_HEAD.some((x, i) => norm(table[0]?.[i]).trim() !== norm(x))) throw new Error("Οι στήλες δεν ταιριάζουν με το πρότυπο: " + EMP_HEAD.join(", "));
    const stores = S.lists.stores.map((s) => s.name), comps = S.lists.companies.map((c) => c.name);
    const seen = new Set(), ex = new Set(existing.map((e) => e.code));
    const rows = table.slice(1).filter((r) => r.some((x) => String(x).trim())).map((r, i) => {
      const [code, first, last, store, company, status] = r.map((x) => String(x ?? "").trim());
      let problem = "";
      if (!code || !first || !last) problem = "Λείπουν στοιχεία";
      else if (seen.has(code)) problem = "Διπλός κωδικός";
      else if (!stores.includes(store)) problem = "Άγνωστο κατάστημα";
      else if (!comps.includes(company)) problem = "Άγνωστη εταιρεία";
      else if (!["Ενεργός", "Ανενεργός"].includes(status)) problem = "Κατάσταση: Ενεργός ή Ανενεργός";
      seen.add(code);
      return { line: i + 2, code, first, last, store, company, status, problem, isNew: !ex.has(code) };
    });
    const ok = rows.filter((r) => !r.problem), bad = rows.filter((r) => r.problem);
    openDialog(`
      <div class="dlg-head"><h2>Εισαγωγή εργαζομένων</h2><button class="icon-btn" data-close>✕</button></div>
      <div class="note ${bad.length ? "warn" : ""}">Νέοι: <strong>${ok.filter((r) => r.isNew).length}</strong> · Ενημερώσεις: <strong>${ok.filter((r) => !r.isNew).length}</strong>${bad.length ? ` · Με πρόβλημα: <strong>${bad.length}</strong> (δεν θα καταχωριστούν)` : ""}</div>
      ${bad.length ? `<ul class="result-list">${bad.slice(0, 40).map((r) => `<li>Γραμμή ${r.line} (${h(r.code || "—")}): ${h(r.problem)}</li>`).join("")}</ul>` : ""}
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="im-ok" ${ok.length ? "" : "disabled"}>Καταχώριση ${ok.length}</button></div>`,
      {
        onOpen() {
          $("#im-ok").onclick = async () => {
            $("#im-ok").disabled = true;
            try {
              const n = await S.api.importEmployees(ok.map(({ code, first, last, store, company, status }) => ({ code, first, last, store, company, status })));
              closeDialog(); invalidate(); toast(`Αποθηκεύτηκαν ${n} εργαζόμενοι.`); rerender();
            } catch (err) { toast(err.message, true); $("#im-ok").disabled = false; }
          };
        },
      });
  } catch (err) { toast(err.message, true); }
}
