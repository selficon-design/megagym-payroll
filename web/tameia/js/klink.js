// Σύνδεσμος ταμείου ρεσεψιόν καταστήματος (tameia/k.html#<κλειδί>)
// • Μόνο υποβολή κλεισίματος (πρωινό 16:00, βραδινό, συμπληρωματικό)· δεν εμφανίζονται προηγούμενα ποσά ή άλλες ενότητες.
// • Το κατάστημα ορίζεται από το κλειδί στον server. Μιλά με τη βάση ΜΟΝΟ με το κλειδί (ρόλος anon)
//   και αποσυνδέει όποιον διαχειριστή ήταν συνδεδεμένος στον browser.
import { $, $$, h, eur, amount, dmy, dayName, readReceipt, loadScript, SHIFT_GR, METHOD_GR } from "./common.js";

const KEY = "mg-cashlink-key";
const ss = { get(k) { try { return sessionStorage.getItem(k); } catch { return null; } }, set(k, v) { try { sessionStorage.setItem(k, v); } catch {} } };
const body = () => $("#lk-body");

function readToken() {
  const raw = decodeURIComponent(location.hash.replace(/^#\/?/, "").replace(/^k=/, "")).trim();
  if (/^[A-Za-z0-9_-]{32,200}$/.test(raw)) { ss.set(KEY, raw); history.replaceState(null, "", location.pathname + location.search); return raw; }
  if (location.hash) history.replaceState(null, "", location.pathname + location.search);
  return ss.get(KEY);
}
async function dropAdminSession(cfg) {
  try {
    const admin = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: true, autoRefreshToken: false, detectSessionInUrl: false, storageKey: "mega-payroll-auth" } });
    await admin.auth.signOut({ scope: "local" });
  } catch {}
  try { localStorage.removeItem("mega-payroll-auth"); for (const k of Object.keys(localStorage)) if (/^sb-.*-auth-token$/.test(k)) localStorage.removeItem(k); } catch {}
}

function screen(title, text, { ok = false, again = false } = {}) {
  body().innerHTML = `<div class="k-sign"><div class="k-done">${ok ? `<div class="tick">✓</div>` : ""}<h1 style="font-size:28px">${h(title)}</h1>
    ${text ? `<p class="muted" style="font-size:17px;margin-top:10px">${text}</p>` : ""}
    ${again ? `<div class="k-actions" style="justify-content:center"><button class="btn primary" id="cl-again">Νέο κλείσιμο</button></div>` : ""}</div></div>`;
  $("#cl-again") && ($("#cl-again").onclick = () => start());
}

let api, T, I, F;
const blank = () => ({ emp: "", date: I.today, shift: "", counted: "", pos: "", iris: "", note: "", livepay: [], expenses: [], refunds: [] });

async function start() {
  body().innerHTML = `<div class="spinner"></div>`;
  if (!T) return screen("Ο σύνδεσμος δεν είναι διαθέσιμος", "Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον manager του καταστήματος.");
  try { I = await api.info(T); }
  catch (e) { return screen("Ο σύνδεσμος δεν είναι διαθέσιμος", h(/έγκυρος|ακυρωθεί/.test(e.message) ? "Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον manager του καταστήματος." : e.message)); }
  $("#lk-sub").textContent = I.store;
  F = blank();
  F.shift = suggestShift(F.date);
  draw();
}

const done = (date) => I.done?.[date] || { status: "open", shifts: [] };
function shiftState(date, s) {
  const d = done(date);
  if (d.status !== "open") return "Η ημέρα έχει ελεγχθεί";
  if (s !== "supplement" && d.shifts.includes(s)) return "Έχει υποβληθεί";
  if (s === "supplement" && !d.shifts.includes("evening")) return "Μετά το βραδινό";
  return "";
}
function suggestShift(date) {
  for (const s of ["morning", "evening", "supplement"]) if (!shiftState(date, s)) return s;
  return "";
}

function rowsHtml(kind) {
  if (kind === "livepay") return F.livepay.map((x, i) => `<div class="cl-row" data-kind="livepay" data-i="${i}">
      <div class="cl-f2"><label>Πελάτης</label><input data-k="customer" value="${h(x.customer)}" autocomplete="off" maxlength="120"></div>
      <div class="cl-f1"><label>Ποσό</label><input data-k="amount" value="${h(x.amount)}" inputmode="decimal" autocomplete="off" placeholder="0,00"></div>
      <button type="button" class="btn ghost cl-del" data-del aria-label="Αφαίρεση">✕</button></div>`).join("");
  if (kind === "expenses") return F.expenses.map((x, i) => `<div class="cl-row cl-wrap" data-kind="expenses" data-i="${i}">
      <div class="cl-f1"><label>Ποσό</label><input data-k="amount" value="${h(x.amount)}" inputmode="decimal" autocomplete="off" placeholder="0,00"></div>
      <div class="cl-f1"><label>Κατηγορία</label><select data-k="category"><option value="">— επιλέξτε —</option>${I.categories.map((c) => `<option ${x.category === c ? "selected" : ""}>${h(c)}</option>`).join("")}</select></div>
      <div class="cl-f2"><label>Περιγραφή</label><input data-k="description" value="${h(x.description)}" maxlength="300" autocomplete="off"></div>
      <div class="cl-f2"><label>Φωτογραφία παραστατικού</label>
        <label class="btn cl-photo ${x.file ? "has" : ""}"><input type="file" accept="image/*,application/pdf" capture="environment" data-file hidden>${x.file ? "✓ " + h(x.file.name) : "📷 Λήψη / επιλογή"}</label></div>
      <button type="button" class="btn ghost cl-del" data-del aria-label="Αφαίρεση">✕</button></div>`).join("");
  return F.refunds.map((x, i) => `<div class="cl-row cl-wrap" data-kind="refunds" data-i="${i}">
      <div class="cl-f1"><label>Ποσό</label><input data-k="amount" value="${h(x.amount)}" inputmode="decimal" autocomplete="off" placeholder="0,00"></div>
      <div class="cl-f1"><label>Τρόπος</label><select data-k="method"><option value="cash" ${x.method === "cash" ? "selected" : ""}>Μετρητά</option><option value="card" ${x.method === "card" ? "selected" : ""}>Κάρτα</option></select></div>
      <div class="cl-f2"><label>Πελάτης</label><input data-k="customer" value="${h(x.customer)}" maxlength="120" autocomplete="off"></div>
      <div class="cl-f2"><label>Αιτία</label><input data-k="reason" value="${h(x.reason)}" maxlength="300" autocomplete="off"></div>
      <div class="cl-f2"><label>Ενέκρινε</label><select data-k="approver"><option value="">— επιλέξτε —</option>${I.approvers.map((a) => `<option value="${h(a.id)}" ${x.approver === a.id ? "selected" : ""}>${h(a.name)}</option>`).join("")}</select></div>
      <button type="button" class="btn ghost cl-del" data-del aria-label="Αφαίρεση">✕</button></div>`).join("");
}

function netCash() {
  const c = amount(F.counted);
  if (c === null || Number.isNaN(c)) return null;
  return F.shift === "supplement" ? c : Math.max(c - I.float, 0);
}

function draw() {
  const seg = (date) => `<button type="button" class="${F.date === date ? "on" : ""}" data-date="${date}">${date === I.today ? "Σήμερα" : "Χθες"} · ${dayName(date)} ${dmy(date)}</button>`;
  const shiftBtn = (s) => { const st = shiftState(F.date, s); return `<button type="button" class="cl-shift ${F.shift === s ? "on" : ""}" data-shift="${s}" ${st ? "disabled" : ""}><strong>${SHIFT_GR[s]}</strong><span>${st || (s === "supplement" ? "Εισπράξεις μετά το βραδινό" : "Διαθέσιμο")}</span></button>`; };
  const sup = F.shift === "supplement", eve = F.shift === "evening";
  body().innerHTML = `<form class="k-sign cl-form" id="cl-form" novalidate>
    <div class="eyebrow">Κατάστημα</div><h2 style="font-size:26px">${h(I.store)}</h2>
    <div class="grid g2" style="margin-top:12px">
      <div><label for="cl-emp">Εργαζόμενος Ρεσεψιόν</label><select id="cl-emp"><option value="">— επιλέξτε —</option>${I.employees.map((e) => `<option value="${h(e.code)}" ${F.emp === e.code ? "selected" : ""}>${h(e.name)}</option>`).join("")}</select></div>
      <div><label>Ημέρα ταμείου</label><div class="seg cl-seg">${seg(I.today)}${seg(I.yesterday)}</div></div>
    </div>
    <label>Κλείσιμο</label><div class="cl-shifts">${["morning", "evening", "supplement"].map(shiftBtn).join("")}</div>
    ${!F.shift ? `<p class="note warn" style="margin-top:16px">Δεν υπάρχει διαθέσιμο κλείσιμο για αυτή την ημέρα. Για αλλαγές απευθυνθείτε στον manager.</p></form>` : `
    <div class="cl-sec"><h3>Μετρητά</h3>
      <div class="grid g2">
        <div><label for="cl-counted">${sup ? "Επιπλέον μετρητά μετά το βραδινό κλείσιμο" : "Καταμέτρηση μετρητών στο συρτάρι"}</label>
          <input id="cl-counted" inputmode="decimal" autocomplete="off" placeholder="0,00" value="${h(F.counted)}">
          <p class="muted small" style="margin-top:6px">${sup ? "Μόνο τα μετρητά που εισπράχθηκαν μετά το βραδινό κλείσιμο." : `Όλα τα μετρητά του συρταριού, <strong>μαζί</strong> με τα ${eur(I.float)} για ρέστα.`}</p></div>
        <div class="cl-net"><div class="label">Μετρητά βάρδιας ${sup ? "" : `(χωρίς τα ${eur(I.float)})`}</div><div class="value num" id="cl-net">${eur(netCash())}</div>
          ${sup ? "" : `<div class="hint">Τα ${eur(I.float)} μένουν στο συρτάρι για την επόμενη βάρδια.</div>`}</div>
      </div></div>
    ${eve || sup ? `<div class="cl-sec"><h3>Κάρτες & IRIS ημέρας</h3>${sup ? `<p class="muted small">Συμπληρώστε μόνο αν άλλαξαν τα ημερήσια σύνολα μετά το βραδινό κλείσιμο.</p>` : ""}
      <div class="grid g2">
        <div><label for="cl-pos">Πακέτο POS ημέρας (κάρτες)</label><input id="cl-pos" inputmode="decimal" autocomplete="off" placeholder="0,00" value="${h(F.pos)}"></div>
        <div><label for="cl-iris">IRIS — ημερήσιο σύνολο</label><input id="cl-iris" inputmode="decimal" autocomplete="off" placeholder="0,00" value="${h(F.iris)}"></div>
      </div></div>` : ""}
    <div class="cl-sec"><div class="cl-sec-head"><h3>Καταθέσεις πελατών — Live Pay</h3><button type="button" class="btn sm" data-add="livepay">+ Προσθήκη</button></div>
      ${rowsHtml("livepay") || `<p class="muted small">Καμία κατάθεση Live Pay.</p>`}</div>
    <div class="cl-sec"><div class="cl-sec-head"><h3>Έξοδα από το ταμείο</h3><button type="button" class="btn sm" data-add="expenses">+ Προσθήκη</button></div>
      ${rowsHtml("expenses") || `<p class="muted small">Κανένα έξοδο. Κάθε έξοδο χρειάζεται φωτογραφία παραστατικού.</p>`}</div>
    <div class="cl-sec"><div class="cl-sec-head"><h3>Επιστροφές χρημάτων</h3><button type="button" class="btn sm" data-add="refunds">+ Προσθήκη</button></div>
      ${rowsHtml("refunds") || `<p class="muted small">Καμία επιστροφή. Κάθε επιστροφή καταγράφεται με το όνομα εκείνου που την ενέκρινε.</p>`}</div>
    <div class="cl-sec"><label for="cl-note">Σημείωση (προαιρετικά)</label><textarea id="cl-note" maxlength="500" style="min-height:70px">${h(F.note)}</textarea></div>
    <p id="cl-m" class="form-msg"></p>
    <div class="k-actions"><button class="btn primary" id="cl-next">Έλεγχος & υποβολή</button></div></form>`}`;
  bind();
}

function bind() {
  $("#cl-emp").onchange = (e) => (F.emp = e.target.value);
  $$("[data-date]").forEach((b) => (b.onclick = () => { F.date = b.dataset.date; if (shiftState(F.date, F.shift) || !F.shift) F.shift = suggestShift(F.date); draw(); }));
  $$("[data-shift]").forEach((b) => (b.onclick = () => { F.shift = b.dataset.shift; draw(); }));
  if (!F.shift) return;
  $("#cl-counted").oninput = (e) => { F.counted = e.target.value; $("#cl-net").textContent = eur(netCash()); };
  $("#cl-pos") && ($("#cl-pos").oninput = (e) => (F.pos = e.target.value));
  $("#cl-iris") && ($("#cl-iris").oninput = (e) => (F.iris = e.target.value));
  $("#cl-note").oninput = (e) => (F.note = e.target.value);
  $$("[data-add]").forEach((b) => (b.onclick = () => {
    const k = b.dataset.add;
    F[k].push(k === "livepay" ? { customer: "", amount: "" } : k === "expenses" ? { amount: "", category: "", description: "", file: null } : { amount: "", method: "cash", customer: "", reason: "", approver: I.approvers.length === 1 ? I.approvers[0].id : "" });
    draw();
    const rows = $$(`.cl-row[data-kind="${k}"]`); rows[rows.length - 1]?.querySelector("input")?.focus();
  }));
  $$(".cl-row").forEach((row) => {
    const list = F[row.dataset.kind], i = Number(row.dataset.i);
    $$("[data-k]", row).forEach((inp) => (inp.oninput = inp.onchange = () => (list[i][inp.dataset.k] = inp.value)));
    $("[data-del]", row).onclick = () => { list.splice(i, 1); draw(); };
    const f = $("[data-file]", row);
    if (f) f.onchange = async () => {
      const lab = f.closest("label"); lab.lastChild.textContent = "Επεξεργασία…";
      try { list[i].file = await readReceipt(f.files[0]); } catch (e) { list[i].file = null; $("#cl-m").textContent = e.message; }
      draw();
    };
  });
  $("#cl-form").onsubmit = (ev) => { ev.preventDefault(); review(); };
}

// Έλεγχος στην οθόνη (ο server ελέγχει ξανά τα πάντα)
function collect() {
  const err = (m) => { throw new Error(m); };
  if (!F.emp) err("Επιλέξτε εργαζόμενο.");
  const counted = amount(F.counted);
  if (counted === null || Number.isNaN(counted)) err(F.shift === "supplement" ? "Συμπληρώστε τα επιπλέον μετρητά (0 αν δεν υπάρχουν)." : "Συμπληρώστε την καταμέτρηση μετρητών.");
  if (F.shift !== "supplement" && counted < I.float) err(`Η καταμέτρηση περιλαμβάνει και τα ${eur(I.float)} για ρέστα· ελέγξτε το ποσό.`);
  const p = { date: F.date, shift: F.shift, employee_code: F.emp, counted_cash: counted, note: F.note.trim() || null, livepay: [], expenses: [], refunds: [] };
  if (F.shift === "evening" || F.shift === "supplement") {
    const pos = amount(F.pos), iris = amount(F.iris);
    if (F.shift === "evening" && (pos === null || Number.isNaN(pos))) err("Συμπληρώστε το πακέτο POS (0 αν δεν υπάρχουν κάρτες).");
    if (F.shift === "evening" && (iris === null || Number.isNaN(iris))) err("Συμπληρώστε το ημερήσιο σύνολο IRIS (0 αν δεν υπάρχει).");
    if (Number.isNaN(pos) || Number.isNaN(iris)) err("Μη έγκυρο ποσό POS ή IRIS.");
    if (pos !== null) p.pos_cards = pos;
    if (iris !== null) p.iris_total = iris;
  }
  F.livepay.forEach((x, i) => { const a = amount(x.amount); if (x.customer.trim().length < 2 || !(a > 0)) err(`Live Pay ${i + 1}: συμπληρώστε πελάτη και ποσό.`); p.livepay.push({ customer: x.customer.trim(), amount: a }); });
  F.expenses.forEach((x, i) => {
    const a = amount(x.amount);
    if (!(a > 0) || !x.category || x.description.trim().length < 2) err(`Έξοδο ${i + 1}: συμπληρώστε ποσό, κατηγορία και περιγραφή.`);
    if (!x.file) err(`Έξοδο ${i + 1}: επισυνάψτε φωτογραφία του παραστατικού.`);
    p.expenses.push({ amount: a, category: x.category, description: x.description.trim(), date: F.date, file: x.file });
  });
  F.refunds.forEach((x, i) => {
    const a = amount(x.amount);
    if (!(a > 0) || x.customer.trim().length < 2 || x.reason.trim().length < 2) err(`Επιστροφή ${i + 1}: συμπληρώστε ποσό, πελάτη και αιτία.`);
    if (!x.approver) err(`Επιστροφή ${i + 1}: επιλέξτε ποιος την ενέκρινε.`);
    p.refunds.push({ amount: a, method: x.method, customer: x.customer.trim(), reason: x.reason.trim(), approver: x.approver });
  });
  return p;
}

function review() {
  let p;
  try { p = collect(); } catch (e) { $("#cl-m").textContent = e.message; return; }
  const emp = I.employees.find((e) => e.code === F.emp)?.name;
  const sum = (a) => a.reduce((s, x) => s + x.amount, 0);
  const net = p.shift === "supplement" ? p.counted_cash : p.counted_cash - I.float;
  body().innerHTML = `<div class="k-sign">
    <div class="eyebrow">Έλεγχος πριν από την υποβολή</div><h2 style="font-size:24px">${h(SHIFT_GR[p.shift])} · ${dayName(p.date)} ${dmy(p.date)}</h2>
    <p class="muted" style="margin-top:4px">${h(I.store)} · ${h(emp)}</p>
    <dl class="kv cl-kv">
      <dt>${p.shift === "supplement" ? "Επιπλέον μετρητά" : "Καταμέτρηση συρταριού"}</dt><dd class="num">${eur(p.counted_cash)}</dd>
      ${p.shift === "supplement" ? "" : `<dt>Ρέστα που μένουν</dt><dd class="num">${eur(I.float)}</dd>`}
      <dt>Μετρητά βάρδιας</dt><dd class="num"><strong>${eur(net)}</strong></dd>
      ${p.pos_cards !== undefined ? `<dt>Πακέτο POS ημέρας</dt><dd class="num">${eur(p.pos_cards)}</dd>` : ""}
      ${p.iris_total !== undefined ? `<dt>IRIS ημέρας</dt><dd class="num">${eur(p.iris_total)}</dd>` : ""}
      <dt>Live Pay</dt><dd>${p.livepay.length ? `${p.livepay.length} · <span class="num">${eur(sum(p.livepay))}</span>` : "—"}</dd>
      <dt>Έξοδα</dt><dd>${p.expenses.length ? `${p.expenses.length} · <span class="num">${eur(sum(p.expenses))}</span>` : "—"}</dd>
      <dt>Επιστροφές</dt><dd>${p.refunds.length ? p.refunds.map((r) => `${eur(r.amount)} ${METHOD_GR[r.method].toLowerCase()} · ${h(I.approvers.find((a) => a.id === r.approver)?.name)}`).join("<br>") : "—"}</dd>
      ${p.note ? `<dt>Σημείωση</dt><dd>${h(p.note)}</dd>` : ""}
    </dl>
    <p class="note" style="margin-top:16px">Μετά την υποβολή δεν αλλάζει από εδώ. Για διορθώσεις απευθυνθείτε στον manager του καταστήματος.</p>
    <p id="cl-m" class="form-msg"></p>
    <div class="k-actions"><button class="btn" id="cl-back">← Αλλαγές</button><button class="btn primary" id="cl-ok">Υποβολή κλεισίματος</button></div></div>`;
  $("#cl-back").onclick = () => draw();
  $("#cl-ok").onclick = async () => {
    const b = $("#cl-ok"); b.disabled = true; b.textContent = "Υποβολή…";
    try {
      await api.submit(T, p);
      screen("Το κλείσιμο υποβλήθηκε", `${h(SHIFT_GR[p.shift])} · ${dmy(p.date)} · μετρητά βάρδιας ${eur(net)}. Ευχαριστούμε.`, { ok: true, again: true });
    } catch (e) { $("#cl-m").textContent = e.message; b.disabled = false; b.textContent = "Υποβολή κλεισίματος"; }
  };
}

async function boot() {
  const cfg = window.MEGA_CONFIG || {};
  T = readToken();
  if (window.__TAMEIA_LINK_MOCK) { api = window.__TAMEIA_LINK_MOCK; return start(); }
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) return screen("Η σελίδα δεν είναι διαθέσιμη", "Η εφαρμογή δεν έχει ρυθμιστεί.");
  try { await loadScript("../vendor/supabase.js"); } catch (e) { return screen("Δεν ήταν δυνατή η φόρτωση", h(e.message)); }
  await dropAdminSession(cfg);
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: "mega-cashlink-none" } });
  const call = async (name, args) => {
    const { data, error } = await sb.rpc(name, args);
    if (error) throw new Error(/Failed to fetch|NetworkError|network/i.test(error.message || "") ? "Δεν υπάρχει σύνδεση στο internet." : error.message || "Προέκυψε σφάλμα.");
    return data;
  };
  api = { info: (t) => call("cashlink_info", { p_token: t }), submit: (t, p) => call("cashlink_submit", { p_token: t, p }) };
  start();
}
boot();
