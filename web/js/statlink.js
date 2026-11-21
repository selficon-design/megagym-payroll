// Σύνδεσμος στατιστικών Ρεσεψιόν καταστήματος (s.html#<κλειδί>) — έκδοση 3.1.
// • Μόνο υποβολή: επιλογή εργαζομένου Ρεσεψιόν του καταστήματος, ημερομηνία, πεδία· μετά μόνο επιβεβαίωση.
// • Το κατάστημα ορίζεται από το κλειδί στον server. Δεν εμφανίζονται προηγούμενες εγγραφές, αναφορές ή άλλες ενότητες.
// • Μιλά με τον server ΜΟΝΟ με το κλειδί (ρόλος anon)· αποσυνδέει όποιον διαχειριστή ήταν συνδεδεμένος στον browser.
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const h = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const KEY = "mg-statlink-key";
const ss = { get(k) { try { return sessionStorage.getItem(k); } catch { return null; } }, set(k, v) { try { sessionStorage.setItem(k, v); } catch {} } };
const NEW = [["dr", "DR — άμεσες εγγραφές"], ["lost", "LOST"], ["cb", "CB — εγγραφές σε επιστροφή"], ["trials_sent", "Δοκιμαστικά που έστειλε"],
  ["enr_fitness", "Εγγραφές Fitness / GYM"], ["enr_body", "Εγγραφές MEGA BODY"], ["enr_muscle", "Εγγραφές MEGA MUSCLE"], ["enr_from_trials", "Εγγραφές από δοκιμαστικά"]];
const OLD = [...NEW.map(([k, l]) => ["old_" + k, l]), ["old_direct", "Παλιά μέλη — Άμεσο"]];

function loadScript(src) {
  return new Promise((res, rej) => { const s = document.createElement("script"); s.src = src; s.onload = res; s.onerror = () => rej(new Error("Δεν φορτώθηκε η σελίδα. Ελέγξτε τη σύνδεση και ανανεώστε.")); document.head.append(s); });
}
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

const body = () => $("#lk-body");
function screen(title, text, { ok = false, again = false } = {}) {
  body().innerHTML = `<div class="k-sign"><div class="k-done">${ok ? `<div class="tick">✓</div>` : ""}<h1 style="font-size:28px">${h(title)}</h1>
    ${text ? `<p class="muted" style="font-size:17px;margin-top:10px">${text}</p>` : ""}
    ${again ? `<div class="k-actions" style="justify-content:center"><button class="btn primary" id="sl-again">Νέα καταχώριση</button></div>` : ""}</div></div>`;
  $("#sl-again") && ($("#sl-again").onclick = () => start());
}

let api, T;
async function start() {
  body().innerHTML = `<div class="spinner"></div>`;
  if (!T) return screen("Ο σύνδεσμος δεν είναι διαθέσιμος", "Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον manager του καταστήματος.");
  let d;
  try { d = await api.info(T); }
  catch (e) { return screen("Ο σύνδεσμος δεν είναι διαθέσιμος", h(/έγκυρος|ακυρωθεί/.test(e.message) ? "Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον manager του καταστήματος." : e.message)); }
  $("#lk-sub").textContent = d.store;
  const inputs = (list) => list.map(([k, l]) => `<div><label for="f-${k}">${h(l)}</label><input id="f-${k}" data-f="${k}" inputmode="numeric" pattern="[0-9]*" autocomplete="off"></div>`).join("");
  body().innerHTML = `<form class="k-sign" id="sl-form" novalidate>
    <div class="eyebrow">Κατάστημα</div><h2 style="font-size:26px">${h(d.store)}</h2>
    <div class="grid g2" style="margin-top:12px">
      <div><label for="sl-emp">Εργαζόμενος Ρεσεψιόν</label><select id="sl-emp" required><option value="">— επιλέξτε —</option>${d.employees.map((e) => `<option value="${h(e.code)}">${h(e.name)}</option>`).join("")}</select></div>
      <div><label for="sl-date">Ημερομηνία</label><input type="date" id="sl-date" value="${h(d.today)}" max="${h(d.today)}" required></div></div>
    <h3 style="margin-top:18px">Νέα μέλη</h3><div class="grid g2">${inputs(NEW)}</div>
    <h3 style="margin-top:18px">Παλιά μέλη</h3><div class="grid g2">${inputs(OLD)}</div>
    <p class="muted small" style="margin-top:10px">Μόνο ακέραιοι αριθμοί· γράψτε 0 όπου δεν υπάρχει. Οι ενημερώσεις (DR + LOST) υπολογίζονται αυτόματα. Μία καταχώριση ανά εργαζόμενο και ημέρα· διορθώσεις κάνει ο manager μέσα στην εφαρμογή.</p>
    <p id="sl-m" class="form-msg"></p>
    <div class="k-actions"><button class="btn primary" id="sl-ok">Υποβολή</button></div></form>`;
  $("#sl-form").onsubmit = async (ev) => {
    ev.preventDefault();
    const m = $("#sl-m"); m.textContent = "";
    const emp = $("#sl-emp").value, date = $("#sl-date").value;
    if (!emp) return (m.textContent = "Επιλέξτε εργαζόμενο.");
    if (!date) return (m.textContent = "Επιλέξτε ημερομηνία.");
    const values = {};
    for (const inp of $$("[data-f]")) {
      const v = inp.value.trim();
      if (!/^\d{1,6}$/.test(v)) { inp.focus(); return (m.textContent = "Συμπληρώστε όλα τα πεδία με ακέραιους αριθμούς (0 όπου δεν υπάρχει)."); }
      values[inp.dataset.f] = Number(v);
    }
    const b = $("#sl-ok"); b.disabled = true;
    try { await api.submit(T, { employee_code: emp, date, values }); screen("Η καταχώριση υποβλήθηκε", "Ευχαριστούμε.", { ok: true, again: true }); }
    catch (e) { m.textContent = e.message; b.disabled = false; }
  };
}

async function boot() {
  const cfg = window.MEGA_CONFIG || {};
  T = readToken();
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) return screen("Η σελίδα δεν είναι διαθέσιμη", "Η εφαρμογή δεν έχει ρυθμιστεί.");
  try { await loadScript("vendor/supabase.js"); } catch (e) { return screen("Δεν ήταν δυνατή η φόρτωση", h(e.message)); }
  await dropAdminSession(cfg);
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: "mega-statlink-none" } });
  const call = async (name, args) => {
    const { data, error } = await sb.rpc(name, args);
    if (error) throw new Error(/Failed to fetch|NetworkError|network/i.test(error.message || "") ? "Δεν υπάρχει σύνδεση στο internet." : error.message || "Προέκυψε σφάλμα.");
    return data;
  };
  api = { info: (t) => call("statlink_info", { p_token: t }), submit: (t, p) => call("statlink_submit", { p_token: t, p }) };
  start();
}
boot();
