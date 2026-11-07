// Σελίδα προσωπικού συνδέσμου αξιολόγησης (a.html#<κλειδί>).
// • Δεν φορτώνει τίποτα από την υπόλοιπη εφαρμογή και δεν έχει συνδέσμους προς τη διαχείριση.
// • Μόλις ανοίξει, ΑΠΟΣΥΝΔΕΕΙ όποιον διαχειριστή ήταν συνδεδεμένος στον ίδιο browser, ώστε ο εργαζόμενος
//   να μην έχει ενεργή διαχειριστική πρόσβαση από την ίδια οθόνη.
// • Μιλά με τον server ΜΟΝΟ με το κλειδί του συνδέσμου (ρόλος anon). Ο server ελέγχει κλειδί, χρόνο και κατάσταση·
//   σωστές απαντήσεις, βαθμοί και κανόνες βαθμολόγησης δεν έρχονται ποτέ εδώ.

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const h = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const athens = (ts) => new Date(ts).toLocaleString("el-GR", { timeZone: "Europe/Athens", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const hhmm = () => new Date().toLocaleTimeString("el-GR", { hour: "2-digit", minute: "2-digit" });
const KEY = "mg-link-key", DRAFT = "mg-link-draft";
const ss = { get(k) { try { return sessionStorage.getItem(k); } catch { return null; } }, set(k, v) { try { sessionStorage.setItem(k, v); } catch {} }, del(k) { try { sessionStorage.removeItem(k); } catch {} } };

function loadScript(src) {
  return new Promise((res, rej) => { const s = document.createElement("script"); s.src = src; s.onload = res; s.onerror = () => rej(new Error("Δεν φορτώθηκε η σελίδα. Ελέγξτε τη σύνδεση και ανανεώστε.")); document.head.append(s); });
}

/** Κλειδί από το #… της διεύθυνσης· κρατιέται μόνο σε αυτή την καρτέλα και αφαιρείται από τη γραμμή διεύθυνσης. */
function readToken() {
  const raw = decodeURIComponent(location.hash.replace(/^#\/?/, "").replace(/^k=/, "")).trim();
  if (/^[A-Za-z0-9_-]{32,200}$/.test(raw)) {
    if (ss.get(KEY) !== raw) ss.del(DRAFT);
    ss.set(KEY, raw);
    history.replaceState(null, "", location.pathname + location.search);
    return raw;
  }
  if (location.hash) history.replaceState(null, "", location.pathname + location.search);
  return ss.get(KEY);
}

/** Αποσύνδεση κάθε διαχειριστικής συνεδρίας της εφαρμογής από αυτόν τον browser. */
async function dropAdminSession(cfg) {
  try {
    const admin = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: true, autoRefreshToken: false, detectSessionInUrl: false, storageKey: "mega-payroll-auth" } });
    await admin.auth.signOut({ scope: "local" });
  } catch {}
  try {
    localStorage.removeItem("mega-payroll-auth");
    for (const k of Object.keys(localStorage)) if (/^sb-.*-auth-token$/.test(k)) localStorage.removeItem(k);
  } catch {}
  ss.del("mg-fill"); ss.del("mg-fill-return");
}

const body = () => $("#lk-body");
function screen(title, text, { ok = false, retry = false } = {}) {
  body().innerHTML = `<div class="k-sign"><div class="k-done">${ok ? `<div class="tick">✓</div>` : ""}<h1 style="font-size:28px">${h(title)}</h1>
    ${text ? `<p class="muted" style="font-size:17px;margin-top:10px">${text}</p>` : ""}
    ${retry ? `<div class="k-actions" style="justify-content:center"><button class="btn" id="lk-retry">Έλεγχος ξανά</button></div>` : ""}</div></div>`;
  $("#lk-retry") && ($("#lk-retry").onclick = () => start());
}
const SCREENS = {
  invalid: () => screen("Ο σύνδεσμος δεν είναι διαθέσιμος", "Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον υπεύθυνο του καταστήματος."),
  submitted: () => screen("Η αξιολόγησή σας υποβλήθηκε επιτυχώς", "Ευχαριστούμε για τον χρόνο σας. Μπορείτε να κλείσετε αυτή τη σελίδα.", { ok: true }),
  closed: () => screen("Η αξιολόγηση δεν είναι πλέον διαθέσιμη", "Απευθυνθείτε στον υπεύθυνο του καταστήματος."),
  expired: (d) => screen("Η προθεσμία έληξε", `Η αξιολόγηση ήταν διαθέσιμη έως <strong>${h(athens(d.ends_at))}</strong> (ώρα Ελλάδας). Οι απαντήσεις δεν υποβλήθηκαν.`),
  scheduled: (d) => screen("Η αξιολόγηση δεν είναι ακόμη διαθέσιμη", `Θα είναι διαθέσιμη από <strong>${h(athens(d.starts_at))}</strong> έως <strong>${h(athens(d.ends_at))}</strong> (ώρα Ελλάδας).`, { retry: true }),
};
/** Μήνυμα σφάλματος του server → κατάλληλη οθόνη (αν υπάρχει) */
function screenFor(msg, d) {
  if (/έγκυρος|ακυρωθεί/i.test(msg)) return SCREENS.invalid(), true;
  if (/ήδη υποβληθεί/i.test(msg)) return SCREENS.submitted(), true;
  if (/προθεσμία|έληξε/i.test(msg)) return SCREENS.expired(d), true;
  if (/ακόμη διαθέσιμη/i.test(msg)) return SCREENS.scheduled(d), true;
  if (/πλέον διαθέσιμη/i.test(msg)) return SCREENS.closed(), true;
  return false;
}

let api, T, timers = [];
const clearTimers = () => { timers.forEach(clearInterval); timers.forEach(clearTimeout); timers = []; };

async function start() {
  clearTimers();
  body().innerHTML = `<div class="spinner"></div>`;
  if (!T) return SCREENS.invalid();
  let d;
  try { d = await api.get(T); }
  catch (e) { if (!screenFor(e.message, {})) screen("Δεν ήταν δυνατή η φόρτωση", h(e.message), { retry: true }); return; }
  $("#lk-sub").textContent = d.employee ? `${d.employee.name} · ${d.employee.store}` : "";
  if (d.state === "open") return intro(d);
  if (d.state === "scheduled") {
    const wait = Date.parse(d.starts_at) - Date.parse(d.now);
    if (wait > 0 && wait < 3600e3) timers.push(setTimeout(start, wait + 1500));
  }
  return (SCREENS[d.state] || SCREENS.invalid)(d);
}

function intro(d) {
  const draft = readDraft();
  const started = Object.keys(d.answers || {}).length > 0 || !!draft;
  body().innerHTML = `<div class="k-sign">
    <div class="eyebrow">Αξιολόγηση</div><h2 style="font-size:26px">${h(d.title)}</h2>
    ${d.description ? `<p style="margin-top:10px;white-space:pre-wrap">${h(d.description)}</p>` : ""}
    <p style="margin-top:12px"><strong>${h(d.employee.name)}</strong> · ${h(d.employee.store)}</p>
    <div class="deadline">Προθεσμία υποβολής: <strong>${h(athens(d.ends_at))}</strong> (ώρα Ελλάδας)</div>
    <p class="muted" style="margin-top:10px">${d.questions.length} ερωτήσεις. Οι απαντήσεις αποθηκεύονται προσωρινά καθώς προχωράτε, ώστε να μη χαθούν αν ανανεωθεί η σελίδα ή κοπεί η σύνδεση. Η αξιολόγηση ολοκληρώνεται μόνο με την «Οριστική υποβολή», η οποία γίνεται μία φορά. Στις ερωτήσεις αυτοαξιολόγησης δεν υπάρχει σωστή ή λάθος απάντηση.</p>
    <div class="k-actions"><button class="btn primary" id="lk-go">${started ? "Συνέχεια" : "Έναρξη"}</button></div></div>`;
  $("#lk-go").onclick = () => form(d);
}

// Τοπικό αντίγραφο ΜΟΝΟ για απαντήσεις που δεν πρόλαβαν να φτάσουν στον server (διακοπή σύνδεσης)
function readDraft() {
  try { const x = JSON.parse(ss.get(DRAFT) || "null"); return x && x.k === T.slice(0, 16) && x.dirty ? x.answers : null; } catch { return null; }
}
const writeDraft = (answers, dirty) => ss.set(DRAFT, JSON.stringify({ k: T.slice(0, 16), answers, dirty, at: Date.now() }));

function form(d) {
  const restored = readDraft();
  const ans = { ...(d.answers || {}), ...(restored || {}) };
  const offset = Date.parse(d.now) - Date.now();           // ώρα server − ώρα συσκευής
  const ends = Date.parse(d.ends_at);
  let dirty = !!restored, saving = false, sending = false, debounce;
  const sections = [...new Set(d.questions.map((q) => q.section))];
  let n = 0;
  const qHtml = (q) => {
    const v = ans[q.id]; n++;
    let input = "";
    if (q.qtype === "single") input = q.options.map((o) => `<label class="opt"><input type="radio" name="q${q.id}" value="${h(o.key)}" ${v === o.key ? "checked" : ""}> <span>${h(o.label)}</span></label>`).join("");
    if (q.qtype === "multi") input = `<p class="muted small">Επιλέξτε όσες ισχύουν.</p>` + q.options.map((o) => `<label class="opt"><input type="checkbox" name="q${q.id}" value="${h(o.key)}" ${(v || []).includes(o.key) ? "checked" : ""}> <span>${h(o.label)}</span></label>`).join("");
    if (q.qtype === "scale") { const xs = []; for (let x = q.scale_min; x <= q.scale_max; x++) xs.push(x); input = `<div class="scale">${q.scale_min_label ? `<span class="muted small">${h(q.scale_min_label)}</span>` : ""}${xs.map((x) => `<label class="sc"><input type="radio" name="q${q.id}" value="${x}" ${v === x ? "checked" : ""}><span>${x}</span></label>`).join("")}${q.scale_max_label ? `<span class="muted small">${h(q.scale_max_label)}</span>` : ""}</div>`; }
    if (q.qtype === "text") input = `<textarea name="q${q.id}" rows="4" maxlength="4000">${h(v || "")}</textarea>`;
    return `<div class="fq" data-q="${q.id}"><div class="fq-t"><span class="muted">${n}.</span> ${h(q.text)}${q.required ? ` <span class="req">*</span>` : ` <span class="muted small">(προαιρετική)</span>`}</div>${input}</div>`;
  };
  body().innerHTML = `<div class="k-sign"><div class="eyebrow">${h(d.title)}</div>
    <div class="deadline sticky" id="lk-dl">Προθεσμία: <strong>${h(athens(d.ends_at))}</strong> (ώρα Ελλάδας) · <span id="lk-prog"></span> · <span id="lk-saved" class="muted"></span></div>
    ${restored ? `<div class="note" style="margin-top:12px">Επαναφέρθηκαν απαντήσεις που δεν είχαν προλάβει να αποθηκευτούν.</div>` : ""}
    ${sections.map((s) => `<h3 class="fsec">${h(s)}</h3>${d.questions.filter((q) => q.section === s).map(qHtml).join("")}`).join("")}
    <p id="lk-m" class="form-msg"></p>
    <div id="lk-confirm" class="note warn" hidden style="margin-top:12px"><strong>Οριστική υποβολή;</strong> Μετά την υποβολή δεν μπορείτε να αλλάξετε τις απαντήσεις σας.
      <div class="k-actions"><button class="btn" id="lk-no">Πίσω στις απαντήσεις</button><button class="btn primary" id="lk-yes">Ναι, υποβολή</button></div></div>
    <div class="k-actions" id="lk-acts"><button class="btn primary" id="lk-submit">Οριστική υποβολή</button></div></div>`;

  const read = () => {
    for (const q of d.questions) {
      const els = $$(`[name="q${q.id}"]`);
      if (q.qtype === "single") { const c = els.find((x) => x.checked); if (c) ans[q.id] = c.value; else delete ans[q.id]; }
      if (q.qtype === "multi") { const c = els.filter((x) => x.checked).map((x) => x.value); if (c.length) ans[q.id] = c; else delete ans[q.id]; }
      if (q.qtype === "scale") { const c = els.find((x) => x.checked); if (c) ans[q.id] = Number(c.value); else delete ans[q.id]; }
      if (q.qtype === "text") { const t = els[0].value.trim(); if (t) ans[q.id] = t; else delete ans[q.id]; }
    }
    const req = d.questions.filter((q) => q.required);
    $("#lk-prog").textContent = `${req.filter((q) => ans[q.id] !== undefined).length}/${req.length} υποχρεωτικές`;
  };
  const status = (t, bad = false) => { const el = $("#lk-saved"); if (el) { el.textContent = t; el.style.color = bad ? "var(--bad)" : ""; } };
  const save = async () => {
    if (!dirty || saving || sending) return;
    saving = true;
    const snapshot = JSON.stringify(ans);
    try {
      await api.save(T, JSON.parse(snapshot));
      if (JSON.stringify(ans) === snapshot) { dirty = false; writeDraft(ans, false); }
      status("αποθηκεύτηκε " + hhmm());
    } catch (e) {
      if (screenFor(e.message, d)) { clearTimers(); return; }
      status(navigator.onLine ? "δεν αποθηκεύτηκε — νέα προσπάθεια σε λίγο" : "χωρίς σύνδεση — οι απαντήσεις κρατούνται εδώ και θα αποθηκευτούν μόλις επανέλθει", true);
    } finally { saving = false; }
  };
  const changed = () => { read(); dirty = true; writeDraft(ans, true); $(".fq.missing")?.classList.remove("missing"); $("#lk-m").textContent = ""; clearTimeout(debounce); debounce = setTimeout(save, 1000); };
  $$(".fq input, .fq textarea").forEach((x) => (x.oninput = x.onchange = changed));
  read();
  status(d.saved_at ? "αποθηκεύτηκε" : "");
  if (restored) save();

  // Επανάληψη αποθήκευσης όταν επανέλθει η σύνδεση· έλεγχος προθεσμίας με την ώρα του server
  const online = () => save();
  window.addEventListener("online", online);
  timers.push(setInterval(save, 15000));
  timers.push(setInterval(() => {
    const left = ends - (Date.now() + offset);
    if (left <= 0) { clearTimers(); window.removeEventListener("online", online); return SCREENS.expired(d); }
    if (left < 5 * 60e3) { $("#lk-dl").style.background = "var(--bad-soft)"; $("#lk-dl").style.color = "var(--bad)"; }
  }, 5000));

  $("#lk-submit").onclick = () => {
    read();
    const miss = d.questions.filter((q) => q.required && ans[q.id] === undefined);
    $$(".fq").forEach((x) => x.classList.toggle("missing", miss.some((q) => q.id === x.dataset.q)));
    if (miss.length) { $("#lk-m").textContent = `Συμπληρώστε ${miss.length === 1 ? "1 υποχρεωτική ερώτηση" : `${miss.length} υποχρεωτικές ερωτήσεις`} (σημειώνονται με κόκκινο).`; $(".fq.missing").scrollIntoView({ behavior: "smooth", block: "center" }); return; }
    $("#lk-confirm").hidden = false; $("#lk-acts").hidden = true; $("#lk-yes").focus();
  };
  $("#lk-no").onclick = () => { $("#lk-confirm").hidden = true; $("#lk-acts").hidden = false; };
  $("#lk-yes").onclick = async () => {
    if (sending) return;                                    // προστασία από διπλό πάτημα (και ο server δέχεται μία μόνο υποβολή)
    sending = true; clearTimeout(debounce);
    const btn = $("#lk-yes"); btn.disabled = true; $("#lk-no").disabled = true; btn.textContent = "Υποβολή…";
    try {
      await api.submit(T, ans);
      clearTimers(); window.removeEventListener("online", online); ss.del(DRAFT);
      SCREENS.submitted();
    } catch (e) {
      sending = false;
      if (screenFor(e.message, d)) { clearTimers(); ss.del(DRAFT); return; }
      btn.disabled = false; $("#lk-no").disabled = false; btn.textContent = "Ναι, υποβολή";
      $("#lk-m").textContent = /fetch|network|σύνδεση/i.test(e.message) ? "Δεν υπάρχει σύνδεση. Οι απαντήσεις σας κρατούνται· δοκιμάστε ξανά την υποβολή σε λίγο." : e.message;
    }
  };
}

async function boot() {
  const cfg = window.MEGA_CONFIG || {};
  T = readToken();
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) return screen("Η σελίδα δεν είναι διαθέσιμη", "Η εφαρμογή δεν έχει ρυθμιστεί.");
  try { await loadScript("vendor/supabase.js"); }
  catch (e) { return screen("Δεν ήταν δυνατή η φόρτωση", h(e.message), { retry: false }); }
  await dropAdminSession(cfg);
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: "mega-link-none" } });
  const call = async (name, args) => {
    const { data, error } = await sb.rpc(name, args);
    if (error) throw new Error(/Failed to fetch|NetworkError|network/i.test(error.message || "") ? "Δεν υπάρχει σύνδεση στο internet." : error.message || "Προέκυψε σφάλμα.");
    return data;
  };
  api = {
    get: (t) => call("link_get", { p_token: t }),
    save: (t, a) => call("link_save", { p_token: t, p_answers: a }),
    submit: (t, a) => call("link_submit", { p_token: t, p_answers: a }),
  };
  // Νέος σύνδεσμος στην ίδια καρτέλα (π.χ. ο manager ανοίγει τον επόμενο εργαζόμενο)
  window.addEventListener("hashchange", () => { if (location.hash.length > 30) { T = readToken(); $("#lk-sub").textContent = ""; start(); } });
  start();
}

boot();
