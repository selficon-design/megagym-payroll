// Εκκίνηση εφαρμογής, μενού και πλοήγηση
import { S, can, role, getStatus, invalidate, setMonth } from "./core.js";
import { $, $$, h, toast, monthLabel, ROLE_GR, closeDialog } from "./util.js";
import { overview, pending, prepare, declarations, employees } from "./views-main.js";
import { tablet, assistant, audit, users, settings, backup, account } from "./views-more.js";
import { requests, requestNew, requestView } from "./views-hr.js";
import { employeeCard } from "./views-card.js";
import { statsEntry, statsReport } from "./views-stats.js";
import { assessments, assessmentView, assessRun, assessReports } from "./views-assess.js";
import { templates } from "./views-admin.js";
import { afterFillReturn } from "./fill-launch.js";

const live = () => S.api?.mode !== "demo";
const ROUTES = [
  { id: "overview", title: "Επισκόπηση", ico: "◫", group: "Μισθοδοσία", render: overview, show: can.payroll },
  { id: "pending", title: "Εκκρεμότητες", ico: "◔", group: "Μισθοδοσία", render: pending, show: can.payroll, count: true },
  { id: "prepare", title: "Προετοιμασία", ico: "✎", group: "Μισθοδοσία", render: prepare, show: can.prepare },
  { id: "tablet", title: "Tablet καταστήματος", ico: "▣", group: "Μισθοδοσία", render: tablet, show: can.sign },
  { id: "declarations", title: "Δηλώσεις", ico: "▤", group: "Μισθοδοσία", render: declarations, show: can.payroll },
  { id: "employees", title: "Εργαζόμενοι", ico: "♙", group: "Προσωπικό", render: employees, show: can.payroll },
  { id: "requests", title: "Αιτήματα & Αναφορές", ico: "✉", group: "Προσωπικό", render: requests, show: () => can.requests() && live() },
  { id: "stats-entry", title: "Ημερήσια στατιστικά", ico: "▦", group: "Προσωπικό", render: statsEntry, show: () => can.statsEntry() && live() },
  { id: "stats-report", title: "Αναφορές στατιστικών", ico: "↗", group: "Προσωπικό", render: statsReport, show: () => can.statsReports() && live() },
  { id: "assessments", title: "Αξιολογήσεις", ico: "☑", group: "Προσωπικό", render: assessments, show: () => can.assessResults() && live() },
  { id: "assess-run", title: "Έναρξη αξιολόγησης", ico: "▶", group: "Προσωπικό", render: assessRun, show: () => can.assessOpen() && live() },
  { id: "assistant", title: "Βοηθός AI", ico: "✦", group: "Προσωπικό", render: assistant, show: can.payroll },
  { id: "templates", title: "Πρότυπα κειμένων", ico: "¶", group: "Διαχείριση", render: templates, show: () => can.templates() && live() },
  { id: "audit", title: "Ιστορικό ενεργειών", ico: "↺", group: "Διαχείριση", render: audit, show: can.audit },
  { id: "backup", title: "Μηνιαίο backup", ico: "⇩", group: "Διαχείριση", render: backup, show: can.backup },
  { id: "users", title: "Χρήστες", ico: "🔑", group: "Διαχείριση", render: users, show: can.users },
  { id: "settings", title: "Ρυθμίσεις", ico: "⚙", group: "Διαχείριση", render: settings, show: can.settings },
  { id: "account", title: "Ο λογαριασμός μου", ico: "◉", group: "Λογαριασμός", render: account, show: () => true },
  // Σελίδες χωρίς δική τους θέση στο μενού
  { id: "request", title: "Αίτημα", group: "", render: requestView, show: () => can.requests() && live(), hidden: true, parent: "requests" },
  { id: "request-new", title: "Νέο αίτημα", group: "", render: requestNew, show: () => can.createRequests() && live(), hidden: true, parent: "requests" },
  { id: "employee", title: "Καρτέλα εργαζομένου", group: "", render: employeeCard, show: () => live(), hidden: true, parent: "employees" },
  { id: "assessment", title: "Ερωτηματολόγιο", group: "", render: assessmentView, show: () => can.assessResults() && live(), hidden: true, parent: "assessments" },
  { id: "assess-reports", title: "Αναφορές αξιολογήσεων", group: "", render: assessReports, show: () => can.assessResults() && live(), hidden: true, parent: "assessments" },
];
const homeRoute = () => ROUTES.find((r) => r.show() && !r.hidden) || ROUTES.find((r) => r.id === "account");

function parseHash() {
  const [path, qs] = location.hash.replace(/^#\/?/, "").split("?");
  return { id: path || "overview", params: new URLSearchParams(qs || "") };
}

function drawNav(openCount) {
  let html = "", group = "";
  for (const r of ROUTES.filter((r) => r.show() && !r.hidden)) {
    if (r.group !== group) { group = r.group; html += `<div class="nav-group">${group}</div>`; }
    html += `<a href="#/${r.id}" data-id="${r.id}"><span class="ico">${r.ico}</span>${r.title}${r.count && openCount ? `<span class="count">${openCount}</span>` : ""}</a>`;
  }
  $("#nav").innerHTML = html;
  markActive();
}
function markActive() {
  const { id } = parseHash();
  const parent = ROUTES.find((r) => r.id === id)?.parent || id;
  $$("#nav a").forEach((a) => a.classList.toggle("active", a.dataset.id === parent));
}
async function refreshCount() {
  if (!can.payroll()) return drawNav(0);
  try { const rows = await getStatus(); drawNav(rows.filter((r) => r.status !== "signed").length); } catch { drawNav(0); }
}

let renderSeq = 0;
async function route() {
  const { id, params } = parseHash();
  const r = ROUTES.find((x) => x.id === id && x.show()) || homeRoute();
  $("#app").classList.remove("menu-open");
  closeDialog();
  markActive();
  $("#page-title").textContent = r.title;
  $("#page-sub").textContent = r.group === "Μισθοδοσία" ? monthLabel(S.month) : "";
  $(".month-pick").hidden = r.group !== "Μισθοδοσία";
  const seq = ++renderSeq;
  const v = $("#view");
  v.innerHTML = `<div class="empty"><div class="spinner"></div></div>`;
  try {
    await r.render(params);
  } catch (e) {
    if (seq !== renderSeq) return;
    console.error(e);
    v.innerHTML = `<div class="card"><div class="empty"><div class="big">⚠︎</div><strong>Δεν φορτώθηκαν τα δεδομένα</strong><p class="muted" style="margin-top:6px">${h(e.message)}</p><button class="btn" style="margin-top:14px" id="retry">Δοκιμή ξανά</button></div></div>`;
    $("#retry").onclick = () => { invalidate(); route(); };
  }
  refreshCount();
}

function drawMe() {
  $("#me-box").innerHTML = `<strong>${h(S.me.name)}</strong><span>${h(S.me.email)}</span><br><span class="role-chip">${ROLE_GR[S.me.role]}${S.me.store ? " · " + h(S.me.store) : ""}</span>`;
}

function drawDemoBar() {
  if (S.api.mode !== "demo") return;
  const bar = $("#demo-bar");
  bar.hidden = false;
  bar.innerHTML = `<strong>Λειτουργία επίδειξης</strong><span>Φανταστικά δεδομένα, μόνο σε αυτόν τον browser. Δοκιμάστε κάθε ρόλο:</span>
    <select id="demo-as">${S.api.demoUsers().map((u) => `<option value="${h(u.email)}" ${u.email === S.api.demoAs() ? "selected" : ""}>${h(u.name)}</option>`).join("")}</select>`;
  $("#demo-as").onchange = async (e) => {
    S.api.demoSwitch(e.target.value);
    S.me = await S.api.session(); S.lists = await S.api.lists(); S.chat = []; S.filters = {};
    invalidate(); drawMe(); drawNav(0); route();
  };
}

async function showApp() {
  S.lists = await S.api.lists();
  $("#login").hidden = true; $("#boot").hidden = true; $("#app").hidden = false;
  $("#global-month").value = S.month;
  drawMe(); drawDemoBar(); drawNav(0);
  await afterFillReturn();
  route();
}

function showLogin(msg) {
  $("#boot").hidden = true; $("#app").hidden = true; $("#login").hidden = false;
  if (msg) $("#login-msg").textContent = msg;
  if (S.api.mode === "demo") {
    $("#login-email").value = "owner@demo.gr"; $("#login-password").value = "demo1234";
    $("#login-msg").className = "form-msg ok";
    $("#login-msg").textContent = "Λειτουργία επίδειξης: πατήστε «Είσοδος». Λογαριασμοί: owner@demo.gr, hr@demo.gr, glyfada@demo.gr.";
  }
  $("#login-email").focus();
}

async function boot() {
  const cfg = window.MEGA_CONFIG || {};
  // Απομονωμένη φόρμα εργαζομένου: δεν φορτώνεται τίποτε άλλο από την εφαρμογή
  let fill = null;
  try { fill = JSON.parse(sessionStorage.getItem("mg-fill") || "null"); } catch {}
  if (fill?.token && cfg.supabaseUrl) {
    try { const { bootFill } = await import("./fill.js"); return await bootFill(cfg, fill); }
    catch (e) { $("#boot").innerHTML = `<div style="color:#fff;text-align:center;padding:20px">Δεν φορτώθηκε η φόρμα.<br><small>${h(e.message)}</small></div>`; return; }
  }
  try {
    if (cfg.supabaseUrl && cfg.supabaseAnonKey) {
      const { createSupabaseApi } = await import("./api-supabase.js");
      S.api = await createSupabaseApi({ url: cfg.supabaseUrl, anonKey: cfg.supabaseAnonKey });
    } else {
      const { createDemoApi } = await import("./api-demo.js");
      S.api = createDemoApi();
    }
  } catch (e) {
    $("#boot").innerHTML = `<div style="color:#fff;text-align:center;padding:20px">Δεν ήταν δυνατή η φόρτωση της εφαρμογής.<br><small>${h(e.message)}</small></div>`;
    return;
  }

  S.api.onAuthChange(() => { if (S.me) location.reload(); });

  $("#login-form").onsubmit = async (e) => {
    e.preventDefault();
    const btn = e.submitter || $("#login-form button"); btn.disabled = true;
    $("#login-msg").className = "form-msg"; $("#login-msg").textContent = "";
    try {
      await S.api.signIn($("#login-email").value, $("#login-password").value);
      const me = await S.api.session();
      if (!me?.role) { await S.api.signOut(); throw new Error("Ο λογαριασμός δεν έχει πρόσβαση. Επικοινωνήστε με τη Γενική Διευθύντρια."); }
      S.me = me; await showApp();
    } catch (err) { $("#login-msg").textContent = err.message; }
    btn.disabled = false;
  };

  $("#open-menu").onclick = () => $("#app").classList.add("menu-open");
  $("#close-menu").onclick = $("#scrim").onclick = () => $("#app").classList.remove("menu-open");
  $("#global-month").onchange = (e) => { if (!e.target.value) return; setMonth(e.target.value); invalidate(); route(); };
  window.addEventListener("hashchange", route);
  window.addEventListener("mg:rerender", () => { invalidate(); route(); });
  window.addEventListener("online", () => toast("Η σύνδεση επανήλθε."));
  window.addEventListener("offline", () => toast("Χωρίς σύνδεση internet. Οι αλλαγές δεν θα αποθηκευτούν.", true));

  try {
    const me = await S.api.session();
    if (me?.role) { S.me = me; await showApp(); }
    else { if (me) await S.api.signOut(); showLogin(me ? "Ο λογαριασμός δεν έχει πρόσβαση." : ""); }
  } catch (e) { showLogin(e.message); }

  if (!cfg.noServiceWorker && "serviceWorker" in navigator && location.protocol === "https:") {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }
}

boot();
