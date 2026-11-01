// Οθόνες: Tablet καταστήματος, Βοηθός AI, Ιστορικό, Χρήστες, Ρυθμίσεις, Backup, Λογαριασμός
import { S, can, role, getStatus, invalidate, visibleStores, activeStores } from "./core.js";
import { $, $$, h, badge, money, monthLabel, dateTime, relTime, statementText, toast, openDialog, closeDialog, confirmBox, norm, ROLE_GR, downloadXlsx, STATUS, dmy } from "./util.js";
import { signaturePad } from "./signature.js";
import { backupZip } from "./pdf.js";
import { specialtiesBlock, bindSpecialties, trainerScopeDialog } from "./views-admin.js";
import { rerender } from "./views-main.js";

const view = () => $("#view");

// ═══════════════════════ Tablet καταστήματος ═══════════════════════
export async function tablet() {
  if (!can.sign()) return (view().innerHTML = `<div class="card empty">Η λειτουργία tablet είναι για λογαριασμούς καταστημάτων.</div>`);
  const stores = visibleStores();
  const st = await getStatus().catch(() => []);
  const cnt = (s) => st.filter((r) => r.store === s && r.status === "pending").length;
  const best = stores.slice().sort((a, b) => cnt(b) - cnt(a))[0];
  const total = role() === "manager" ? cnt(S.me.store) : st.filter((r) => r.status === "pending").length;
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(monthLabel(S.month))}</div><h1>Tablet καταστήματος</h1>
    <p class="muted">Πλήρης οθόνη μόνο για υπογραφές. Ο εργαζόμενος βρίσκει το όνομά του, διαβάζει τη δήλωση και υπογράφει. Δεν βλέπει τίποτε άλλο.</p></div></div>
  <div class="card" style="max-width:640px">
    ${role() === "manager" ? `<p>Κατάστημα: <strong>${h(S.me.store)}</strong> · ${cnt(S.me.store)} δηλώσεις προς υπογραφή</p>` : `<label>Κατάστημα</label><select id="tb-store">${stores.map((s) => `<option value="${h(s)}" ${s === best ? "selected" : ""}>${h(s)} (${cnt(s)} προς υπογραφή)</option>`).join("")}</select>`}
    ${total ? "" : `<div class="note warn" style="margin-top:16px">Δεν υπάρχουν δηλώσεις προς υπογραφή για ${h(monthLabel(S.month))}. Στο tablet εμφανίζονται μόνο οι εργαζόμενοι με έτοιμη δήλωση. ${can.prepare() ? `<a href="#/prepare">Ετοιμάστε τις δηλώσεις εδώ →</a>` : ""}</div>`}
    <div class="note" style="margin-top:16px">Για έξοδο από τη λειτουργία tablet θα ζητηθεί ο κωδικός του λογαριασμού σας.</div>
    <button class="btn primary block" id="tb-go">▣ Έναρξη λειτουργίας tablet</button>
  </div>`;
  $("#tb-go").onclick = () => startKiosk(role() === "manager" ? S.me.store : $("#tb-store").value);
}

let wakeLock;
async function startKiosk(store) {
  const k = $("#kiosk");
  k.hidden = false; document.body.style.overflow = "hidden";
  try { await document.documentElement.requestFullscreen?.(); } catch {}
  try { wakeLock = await navigator.wakeLock?.request("screen"); } catch {}
  const state = { q: "", idle: null };
  const head = `<div class="k-head"><img src="mega-gym-logo.png" alt="MEGA GYM"><div class="k-title"><strong>${h(store)}</strong><span>Δηλώσεις ${h(monthLabel(S.month))}</span></div><button class="btn" id="k-exit">Έξοδος</button></div>`;

  const resetIdle = () => { clearTimeout(state.idle); state.idle = setTimeout(() => list(), 120000); };

  async function list() {
    clearTimeout(state.idle);
    invalidate();
    let all = [];
    try { all = (await getStatus()).filter((r) => r.store === store); }
    catch (e) { k.innerHTML = head + `<div class="k-body"><h1>Δεν υπάρχει σύνδεση</h1><p class="muted">${h(e.message)}</p><button class="btn primary" id="k-retry" style="margin-top:20px">Δοκιμή ξανά</button></div>`; bindExit(); $("#k-retry").onclick = list; return; }
    const rows = all.filter((r) => r.status === "pending");
    const draw = () => {
      const match = (r) => !state.q || norm(`${r.first} ${r.last} ${r.code}`).includes(norm(state.q));
      const shown = rows.filter(match);
      // Όταν ψάχνει κάποιος που δεν έχει έτοιμη δήλωση, του εξηγούμε γιατί
      const others = state.q.trim().length >= 2 ? all.filter((r) => r.status !== "pending" && match(r)) : [];
      const note = (r) => r.status === "signed" ? "✓ Έχετε ήδη υπογράψει για αυτόν τον μήνα" : "Η δήλωσή σας δεν έχει ετοιμαστεί ακόμη· ενημερώστε τον υπεύθυνο";
      $("#k-grid").innerHTML =
        shown.map((r) => `<button class="k-card" data-code="${h(r.code)}">${h(r.first)} ${h(r.last)}<span>${h(r.code)}</span></button>`).join("") +
        others.map((r) => `<div class="k-card" style="opacity:.6;cursor:default">${h(r.first)} ${h(r.last)}<span>${note(r)}</span></div>`).join("") ||
        `<p class="muted" style="font-size:18px">${rows.length ? "Δεν βρέθηκε. Δοκιμάστε με το επώνυμο ή τον κωδικό σας." : `Δεν υπάρχουν δηλώσεις προς υπογραφή για ${h(store)} αυτή τη στιγμή.<br><span style="font-size:15px">Ο υπεύθυνος πρέπει πρώτα να τις ετοιμάσει από την «Προετοιμασία».</span>`}</p>`;
      $$("button.k-card").forEach((b) => (b.onclick = () => sign(rows.find((r) => r.code === b.dataset.code))));
    };
    k.innerHTML = head + `<div class="k-body"><h1>Καλώς ήρθατε</h1><p class="muted" style="font-size:18px">Βρείτε το όνομά σας για να υπογράψετε τη μηνιαία δήλωση.</p>
      <input class="k-search" id="k-q" type="search" placeholder="Γράψτε το επώνυμό σας…" autocomplete="off" value="${h(state.q)}"><div class="k-grid" id="k-grid"></div></div>`;
    bindExit();
    $("#k-q").oninput = (e) => { state.q = e.target.value; draw(); };
    draw();
  }

  function sign(r) {
    state.q = "";
    k.innerHTML = head + `<div class="k-body"><div class="k-sign">
      <div class="eyebrow">${h(monthLabel(S.month))} · ${h(r.store)}</div><h2 style="font-size:26px">${h(r.first)} ${h(r.last)}</h2>
      <p class="muted">Διαβάστε προσεκτικά τη δήλωση πριν υπογράψετε.</p>
      <div class="statement">${h(statementText(r.company, r.end_date, r.period, r.amount))}</div>
      <label for="k-name" style="font-size:15px">Ονοματεπώνυμο</label><input id="k-name" maxlength="150" autocomplete="off" placeholder="Γράψτε το ονοματεπώνυμό σας">
      <label style="font-size:15px">Υπογραφή</label><div class="sig-wrap" id="k-pad"></div>
      <p id="k-msg" class="form-msg"></p>
      <div class="k-actions"><button class="btn" id="k-back">← Πίσω</button><button class="btn" id="k-clear">Καθαρισμός</button><button class="btn primary" id="k-ok">Υποβολή δήλωσης</button></div>
    </div></div>`;
    bindExit();
    const pad = signaturePad($("#k-pad"));
    resetIdle();
    k.onpointerdown = resetIdle; k.onkeydown = resetIdle;
    $("#k-back").onclick = () => { pad.destroy(); list(); };
    $("#k-clear").onclick = () => pad.clear();
    $("#k-ok").onclick = async () => {
      const name = $("#k-name").value.trim();
      if (name.length < 3) return ($("#k-msg").textContent = "Γράψτε το ονοματεπώνυμό σας.");
      if (pad.isEmpty()) return ($("#k-msg").textContent = "Η υπογραφή λείπει.");
      const btn = $("#k-ok"); btn.disabled = true; btn.textContent = "Αποθήκευση…";
      try {
        await S.api.sign(r.declaration_id, name, pad.toPng());
        pad.destroy(); clearTimeout(state.idle);
        k.innerHTML = head + `<div class="k-body"><div class="k-done"><div class="tick">✓</div><h1>Ευχαριστούμε, ${h(r.first)}!</h1><p class="muted" style="font-size:18px">Η δήλωσή σας καταχωρίστηκε.</p></div></div>`;
        bindExit();
        setTimeout(list, 3500);
      } catch (e) { $("#k-msg").textContent = e.message; btn.disabled = false; btn.textContent = "Υποβολή δήλωσης"; }
    };
  }

  function bindExit() {
    $("#k-exit").onclick = () => {
      const box = document.createElement("div");
      box.innerHTML = `<div class="k-body"><div class="k-sign" style="max-width:440px"><h2>Έξοδος από tablet</h2><p class="muted">Μόνο για τον υπεύθυνο του καταστήματος.</p>
        <label>Κωδικός λογαριασμού (${h(S.me.email)})</label><input type="password" id="k-pw" autocomplete="current-password">
        <p id="k-pmsg" class="form-msg"></p><div class="k-actions"><button class="btn" id="k-cancel">Άκυρο</button><button class="btn primary" id="k-pok">Έξοδος</button></div></div></div>`;
      const prev = [...k.childNodes].slice(1);
      prev.forEach((n) => n.remove());
      k.append(box.firstChild);
      $("#k-pw").focus();
      $("#k-cancel").onclick = list;
      const go = async () => {
        try { await S.api.verifyPassword($("#k-pw").value); stop(); }
        catch (e) { $("#k-pmsg").textContent = e.message; }
      };
      $("#k-pok").onclick = go;
      $("#k-pw").onkeydown = (e) => { if (e.key === "Enter") go(); };
    };
  }
  function stop() {
    clearTimeout(state.idle);
    k.hidden = true; k.innerHTML = ""; k.onpointerdown = k.onkeydown = null; document.body.style.overflow = "";
    try { document.fullscreenElement && document.exitFullscreen(); } catch {}
    try { wakeLock?.release(); } catch {}
    invalidate(); rerender();
  }
  list();
}

// ═══════════════════════ Βοηθός AI ═══════════════════════
function md(text) {
  // Ασφαλής, απλή μορφοποίηση: **έντονα**, _πλάγια_, λίστες με παύλα
  const esc = h(text);
  const lines = esc.split("\n");
  let html = "", inList = false;
  for (const l of lines) {
    const fm = (s) => s.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>").replace(/(^|\s)_(.+?)_(?=\s|$|[.,;:!?])/g, "$1<em>$2</em>");
    if (/^\s*[-•*]\s+/.test(l)) { if (!inList) { html += "<ul>"; inList = true; } html += `<li>${fm(l.replace(/^\s*[-•*]\s+/, ""))}</li>`; }
    else { if (inList) { html += "</ul>"; inList = false; } if (l.trim()) html += `<p>${fm(l.replace(/^#+\s*/, ""))}</p>`; }
  }
  if (inList) html += "</ul>";
  return html;
}

export async function assistant() {
  const sugg = role() === "manager"
    ? ["Ποιοι δεν έχουν υπογράψει αυτόν τον μήνα;", "Πόσα ποσά υπογράφηκαν αυτόν τον μήνα;", "Δείξε το ιστορικό δηλώσεων ενός εργαζομένου", "Σύγκρινε με τον προηγούμενο μήνα"]
    : ["Ποιοι δεν έχουν υπογράψει αυτόν τον μήνα;", "Σύνοψη μήνα ανά κατάστημα", "Σύνολα ποσών ανά εταιρεία φέτος", "Ποιο κατάστημα καθυστερεί περισσότερο;", ...(can.audit() ? ["Τι άλλαξε τις τελευταίες μέρες;"] : [])];
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Ρωτήστε σε απλά ελληνικά</div><h1>Βοηθός AI</h1>
    <p class="muted">Ψάχνει στα δεδομένα με τα δικαιώματα του λογαριασμού σας${role() === "manager" ? ` (κατάστημα ${h(S.me.store)})` : ""}. Δεν αλλάζει τίποτα.</p></div>
    <button class="btn" id="ai-clear">Νέα συζήτηση</button></div>
  <div class="card chat"><div class="chat-log" id="ai-log"></div>
    <div class="suggest" id="ai-sugg">${sugg.map((s) => `<button class="chip">${h(s)}</button>`).join("")}</div>
    <form class="chat-form" id="ai-form"><textarea id="ai-in" rows="1" placeholder="π.χ. Ποιοι στη Γλυφάδα δεν έχουν υπογράψει τον Οκτώβριο;"></textarea><button class="btn primary">Αποστολή</button></form>
  </div>`;
  const log = $("#ai-log");
  const draw = () => {
    log.innerHTML = S.chat.length ? S.chat.map((m) => `<div class="msg ${m.role === "user" ? "user" : "bot"} ${m.err ? "err" : ""}">${m.role === "user" ? h(m.content) : md(m.content)}</div>`).join("")
      : `<div class="empty" style="margin:auto"><div class="big">✦</div>Γράψτε μια ερώτηση ή διαλέξτε μία από κάτω.</div>`;
    log.scrollTop = log.scrollHeight;
  };
  draw();
  const send = async (text) => {
    text = text.trim(); if (!text) return;
    S.chat.push({ role: "user", content: text }); draw();
    $("#ai-in").value = ""; $("#ai-sugg").hidden = true;
    log.insertAdjacentHTML("beforeend", `<div class="msg bot" id="ai-typing"><span class="typing"><i></i><i></i><i></i></span></div>`); log.scrollTop = log.scrollHeight;
    try {
      const answer = await S.api.ask(S.chat.filter((m) => !m.err).map(({ role, content }) => ({ role, content })));
      S.chat.push({ role: "assistant", content: answer });
    } catch (e) { S.chat.push({ role: "assistant", content: e.message, err: true }); }
    if (location.hash.startsWith("#/assistant")) draw();
  };
  $("#ai-form").onsubmit = (e) => { e.preventDefault(); send($("#ai-in").value); };
  $("#ai-in").onkeydown = (e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(e.target.value); } };
  $$("#ai-sugg .chip").forEach((b) => (b.onclick = () => send(b.textContent)));
  $("#ai-clear").onclick = () => { S.chat = []; assistant(); };
  $("#ai-sugg").hidden = S.chat.length > 0;
}

// ═══════════════════════ Ιστορικό ενεργειών ═══════════════════════
const FIELD_GR = { first: "όνομα", last: "επώνυμο", store: "κατάστημα", company: "εταιρεία", status: "κατάσταση", amount: "ποσό", period: "διάστημα", end_date: "ημερομηνία", name: "όνομα", role: "ρόλος", active: "ενεργός", sort: "σειρά" };
function describe(a) {
  const d = a.details || {};
  const label = d.label || d.employee_name || (d.first ? `${d.first} ${d.last}` : "") || d.name || a.entity_id || "";
  const ch = d.changes ? Object.keys(d.changes).filter((k) => FIELD_GR[k]).map((k) => `${FIELD_GR[k]}: ${d.changes[k].from ?? "—"} → ${d.changes[k].to ?? "—"}`).join(" · ") : "";
  const m = d.month ? ` · ${monthLabel(d.month)}` : "";
  const T = {
    "declarations:insert": ["✎", `Ετοιμάστηκε δήλωση για ${label}${m}${d.amount ? " · " + money(d.amount) : ""}`],
    "declarations:update": ["✎", `Άλλαξε δήλωση του/της ${label}${m}${ch ? " — " + ch : ""}`],
    "declarations:sign": ["✍︎", `Υπέγραψε ο/η ${label}${m}${d.store ? " · " + d.store : ""}`],
    "declarations:void": ["⊘", `Ακυρώθηκε δήλωση του/της ${label}${m}`],
    "employees:insert": ["♙", `Νέος εργαζόμενος: ${label}${d.store ? " · " + d.store : ""}`],
    "employees:update": ["♙", `Αλλαγή εργαζομένου ${label}${ch ? " — " + ch : ""}`],
    "employees:delete": ["♙", `Διαγραφή εργαζομένου ${label}`],
    "employees:import": ["⇧", `Εισαγωγή ${d.count ?? ""} εργαζομένων από Excel`],
    "app_users:insert": ["🔑", `Νέος χρήστης: ${label} (${ROLE_GR[d.role] || d.role || ""})`],
    "app_users:update": ["🔑", `Αλλαγή χρήστη ${a.entity_id}${ch ? " — " + ch : ""}`],
    "app_users:delete": ["🔑", `Διαγραφή χρήστη ${a.entity_id}`],
    "stores:insert": ["⌂", `Νέο κατάστημα: ${label}`], "stores:update": ["⌂", `Αλλαγή καταστήματος ${label}`],
    "companies:insert": ["▦", `Νέα εταιρεία: ${label}`], "companies:update": ["▦", `Αλλαγή εταιρείας ${label}`],
  };
  return T[`${a.entity}:${a.action}`] || ["•", `${a.action} ${a.entity} ${label}`];
}

export async function audit() {
  if (!can.audit()) return (view().innerHTML = `<div class="card empty">Δεν έχετε πρόσβαση στο ιστορικό.</div>`);
  const F = (S.filters.audit ??= { entity: "", q: "" });
  let items = await S.api.audit({ limit: 300, entity: F.entity || undefined });
  const render = () => {
    const shown = items.filter((a) => !F.q || norm(describe(a)[1] + " " + a.actor).includes(norm(F.q)));
    $("#au-list").innerHTML = shown.length ? shown.map((a) => { const [ico, txt] = describe(a); return `<div class="list-item"><div class="avatar">${ico}</div><div class="grow"><div>${h(txt)}</div><div class="muted small">${h(a.actor)} · ${dateTime(a.at)}</div></div></div>`; }).join("")
      : `<div class="empty">Δεν υπάρχουν εγγραφές.</div>`;
  };
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Ποιος έκανε τι και πότε</div><h1>Ιστορικό ενεργειών</h1>
    <p class="muted">Καταγράφεται αυτόματα από τη βάση και δεν τροποποιείται.</p></div>
    <button class="btn" id="au-export">⇩ Excel</button></div>
  <div class="card"><div class="toolbar">
    <input type="search" id="au-q" placeholder="Αναζήτηση" value="${h(F.q)}">
    <select id="au-entity"><option value="">Όλες οι ενέργειες</option><option value="declarations">Δηλώσεις</option><option value="employees">Εργαζόμενοι</option><option value="app_users">Χρήστες</option><option value="stores">Καταστήματα</option></select>
  </div><div id="au-list"></div>
  <div style="text-align:center;margin-top:12px"><button class="btn" id="au-more" ${items.length < 300 ? "hidden" : ""}>Παλαιότερα</button></div></div>`;
  $("#au-entity").value = F.entity;
  render();
  $("#au-q").oninput = (e) => { F.q = e.target.value; render(); };
  $("#au-entity").onchange = (e) => { F.entity = e.target.value; audit(); };
  $("#au-more").onclick = async () => {
    const more = await S.api.audit({ limit: 300, entity: F.entity || undefined, before: items[items.length - 1].at });
    items = items.concat(more); render(); $("#au-more").hidden = more.length < 300;
  };
  $("#au-export").onclick = () => downloadXlsx("Ιστορικό.xlsx", { "Ιστορικό": [["Ημ/νία", "Χρήστης", "Ενέργεια"], ...items.map((a) => [dateTime(a.at), a.actor, describe(a)[1]])] });
}

// ═══════════════════════ Χρήστες ═══════════════════════
export async function users() {
  if (!can.users()) return (view().innerHTML = `<div class="card empty">Μόνο για τη Γενική Διευθύντρια.</div>`);
  const [list, st] = await Promise.all([S.api.users(), S.api.userStatuses()]);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Πρόσβαση</div><h1>Διαχείριση χρηστών</h1>
    <p class="muted">Ποιος μπαίνει στην εφαρμογή και τι βλέπει. Οι εργαζόμενοι δεν χρειάζονται λογαριασμό: υπογράφουν στο tablet του καταστήματος.</p></div>
    <button class="btn primary" id="us-new">+ Νέος χρήστης</button></div>
  <div class="grid g4" style="margin-bottom:16px">
    <div class="card"><span class="badge b-role">Γενική Διευθύντρια</span><p class="small muted" style="margin-top:8px">Τα πάντα: όλα τα καταστήματα, δηλώσεις, υπογραφές, ακυρώσεις, backup, χρήστες, πρότυπα κειμένων, ερωτηματολόγια· τελική απόφαση σε αυξήσεις, συμβάσεις και προειδοποιήσεις.</p></div>
    <div class="card"><span class="badge b-role">HR</span><p class="small muted" style="margin-top:8px">Όλα τα καταστήματα: εργαζόμενοι, δηλώσεις, αιτήματα και αναφορές, αποφάσεις αδειών, προσχέδια προειδοποιήσεων, αναφορές στατιστικών και αξιολογήσεων. Δεν παίρνει υπογραφές.</p></div>
    <div class="card"><span class="badge b-role">Manager</span><p class="small muted" style="margin-top:8px">Μόνο το κατάστημά του: δηλώσεις και υπογραφές, αιτήματα εργαζομένων, αναφορές, ημερήσια στατιστικά, έναρξη αξιολογήσεων.</p></div>
    <div class="card"><span class="badge b-role">Εκπαιδευτής</span><p class="small muted" style="margin-top:8px">Μόνο έναρξη αξιολογήσεων για εργαζόμενους του πεδίου που του ορίζετε. Καμία πρόσβαση σε μισθοδοσία, άδειες, αναφορές ή χρήστες.</p></div>
  </div>
  <div class="card"><div class="table-wrap"><table class="stack"><thead><tr><th>Χρήστης</th><th>Ρόλος</th><th>Λογαριασμός</th><th></th></tr></thead><tbody>
  ${list.map((u) => { const s = st?.[u.email]; return `<tr><td><strong>${h(u.name)}</strong><span class="sub">${h(u.email)}</span></td>
    <td><span class="badge b-role">${ROLE_GR[u.role]}${u.store ? " · " + h(u.store) : ""}</span>${u.role === "trainer" ? ` <button class="btn sm ghost" data-scope="${h(u.email)}">Πεδίο ευθύνης</button>` : ""}</td>
    <td class="small">${!u.active ? `<span class="badge b-voided">Κλειδωμένος</span>` : st === null ? `<span class="muted">—</span>` : s ? `<span class="badge b-signed">Ενεργός</span><span class="sub">${s.lastSignIn ? "Τελ. είσοδος " + relTime(s.lastSignIn) : "Δεν έχει μπει ακόμη"}</span>` : `<span class="badge b-pending">Χωρίς κωδικό</span>`}</td>
    <td class="acts"><div class="row-actions" style="justify-content:flex-end">
      <button class="btn sm" data-edit="${h(u.email)}">Επεξεργασία</button>
      <button class="btn sm" data-pw="${h(u.email)}">Κωδικός</button>
      ${u.email !== S.me.email ? `<button class="btn sm ${u.active ? "danger" : ""}" data-act="${h(u.email)}">${u.active ? "Κλείδωμα" : "Ξεκλείδωμα"}</button><button class="btn sm ghost" data-del="${h(u.email)}">Διαγραφή</button>` : ""}
    </div></td></tr>`; }).join("")}
  </tbody></table></div></div>`;
  $("#us-new").onclick = () => userDialog(null);
  $$("[data-edit]").forEach((b) => (b.onclick = () => userDialog(list.find((u) => u.email === b.dataset.edit))));
  $$("[data-pw]").forEach((b) => (b.onclick = () => passwordDialog(b.dataset.pw)));
  $$("[data-scope]").forEach((b) => (b.onclick = () => trainerScopeDialog(list.find((u) => u.email === b.dataset.scope))));
  $$("[data-act]").forEach((b) => (b.onclick = async () => {
    const u = list.find((x) => x.email === b.dataset.act);
    if (u.active && !(await confirmBox("Κλείδωμα χρήστη", `Ο/Η ${u.name} δεν θα μπορεί να μπει στην εφαρμογή μέχρι να ξεκλειδωθεί.`, { ok: "Κλείδωμα", danger: true }))) return;
    try { await S.api.setActive(u.email, !u.active); toast(u.active ? "Ο χρήστης κλειδώθηκε." : "Ο χρήστης ξεκλειδώθηκε."); users(); } catch (e) { toast(e.message, true); }
  }));
  $$("[data-del]").forEach((b) => (b.onclick = async () => {
    const u = list.find((x) => x.email === b.dataset.del);
    if (!(await confirmBox("Διαγραφή χρήστη", `Διαγραφή του/της ${u.name} (${u.email}); Οι δηλώσεις που καταχώρισε μένουν στο αρχείο.`, { ok: "Διαγραφή", danger: true }))) return;
    try { await S.api.deleteUser(u.email); toast("Ο χρήστης διαγράφηκε."); users(); } catch (e) { toast(e.message, true); }
  }));
}

const genPassword = () => {
  const a = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const r = crypto.getRandomValues(new Uint32Array(10));
  return Array.from(r, (x) => a[x % a.length]).join("");
};

function userDialog(u) {
  const isNew = !u;
  u ??= { email: "", name: "", role: "manager", store: activeStores()[0] };
  openDialog(`
    <div class="dlg-head"><h2>${isNew ? "Νέος χρήστης" : "Επεξεργασία χρήστη"}</h2><button class="icon-btn" data-close>✕</button></div>
    <form id="uf"><div class="grid g2">
      <div><label>Ονοματεπώνυμο</label><input id="uf-name" required maxlength="150" value="${h(u.name)}"></div>
      <div><label>Email</label><input id="uf-email" type="email" required maxlength="254" value="${h(u.email)}" ${isNew ? "" : "readonly"}></div>
      <div><label>Ρόλος</label><select id="uf-role">${["manager", "hr", "owner", ...(S.api.mode === "demo" ? [] : ["trainer"])].map((r) => `<option value="${r}" ${r === u.role ? "selected" : ""}>${ROLE_GR[r]}</option>`).join("")}</select></div>
      <div id="uf-store-box"><label>Κατάστημα</label><select id="uf-store">${activeStores().map((s) => `<option ${s === u.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select></div>
      ${isNew ? `<div style="grid-column:1/-1"><label>Κωδικός πρώτης εισόδου</label><div class="row-actions" style="flex-wrap:nowrap"><input id="uf-pw" minlength="8" required value="${genPassword()}"><button type="button" class="btn" id="uf-gen">Νέος</button></div>
        <p class="muted small" style="margin-top:6px">Δώστε τον στον χρήστη. Μπορεί να τον αλλάξει από «Ο λογαριασμός μου».</p></div>` : ""}
    </div>
    <p id="uf-msg" class="form-msg"></p>
    <div class="dlg-foot"><button type="button" class="btn" data-close>Άκυρο</button><button class="btn primary">Αποθήκευση</button></div></form>`,
    {
      onOpen() {
        const sync = () => ($("#uf-store-box").hidden = $("#uf-role").value !== "manager");
        $("#uf-role").onchange = sync; sync();
        $("#uf-gen") && ($("#uf-gen").onclick = () => ($("#uf-pw").value = genPassword()));
        $("#uf").onsubmit = async (e) => {
          e.preventDefault();
          const v = { email: $("#uf-email").value.trim().toLowerCase(), name: $("#uf-name").value.trim(), role: $("#uf-role").value, store: $("#uf-role").value === "manager" ? $("#uf-store").value : null, active: u.active ?? true };
          try {
            await S.api.saveUser(v);
            if (isNew) {
              const pw = $("#uf-pw").value;
              await S.api.setPassword(v.email, pw);
              shareCredentials(v, pw);
            } else { closeDialog(); toast("Αποθηκεύτηκε."); }
            users();
            if (v.role === "trainer" && isNew) toast("Ορίστε το πεδίο ευθύνης του εκπαιδευτή από «Πεδίο ευθύνης».");
          } catch (err) { $("#uf-msg").textContent = err.message; }
        };
      },
    });
}

function passwordDialog(email) {
  openDialog(`<div class="dlg-head"><h2>Νέος κωδικός</h2><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">${h(email)}</p><label>Κωδικός</label><div class="row-actions" style="flex-wrap:nowrap"><input id="pw-new" minlength="8" value="${genPassword()}"><button class="btn" id="pw-gen">Νέος</button></div>
    <p id="pw-msg" class="form-msg"></p><div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="pw-ok">Ορισμός κωδικού</button></div>`,
    { onOpen() {
      $("#pw-gen").onclick = () => ($("#pw-new").value = genPassword());
      $("#pw-ok").onclick = async () => {
        const pw = $("#pw-new").value;
        if (pw.length < 8) return ($("#pw-msg").textContent = "Τουλάχιστον 8 χαρακτήρες.");
        try { await S.api.setPassword(email, pw); shareCredentials({ email }, pw); users(); } catch (e) { $("#pw-msg").textContent = e.message; }
      };
    } });
}

function shareCredentials(u, pw) {
  const url = location.href.split("#")[0];
  const text = `Είσοδος στην εφαρμογή MEGA GYM Δηλώσεις μισθοδοσίας\n${url}\nEmail: ${u.email}\nΚωδικός: ${pw}`;
  openDialog(`<div class="dlg-head"><h2>Ο λογαριασμός είναι έτοιμος</h2><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Στείλτε αυτά τα στοιχεία στον χρήστη (π.χ. με Viber ή SMS). Ο κωδικός δεν θα ξαναεμφανιστεί.</p>
    <div class="statement" style="font-family:ui-monospace,Consolas,monospace">${h(text)}</div>
    <div class="dlg-foot"><button class="btn" id="sc-copy">Αντιγραφή</button>${navigator.share ? `<button class="btn" id="sc-share">Κοινοποίηση</button>` : ""}<button class="btn primary" data-close>Τέλος</button></div>`,
    { onOpen() {
      $("#sc-copy").onclick = async () => { try { await navigator.clipboard.writeText(text); toast("Αντιγράφηκε."); } catch { toast("Επιλέξτε και αντιγράψτε το κείμενο.", true); } };
      $("#sc-share") && ($("#sc-share").onclick = () => navigator.share({ text }).catch(() => {}));
    } });
}

// ═══════════════════════ Ρυθμίσεις ═══════════════════════
export async function settings() {
  if (!can.settings()) return (view().innerHTML = `<div class="card empty">Μόνο για τη Γενική Διευθύντρια.</div>`);
  const block = (title, kind, items) => `<div class="card"><div class="card-head"><h3>${title}</h3></div>
    ${items.map((x) => `<div class="list-item"><div class="grow"><strong>${h(x.name)}</strong></div><span class="badge ${x.active ? "b-signed" : "b-missing"}">${x.active ? "Ενεργό" : "Ανενεργό"}</span>
      <button class="btn sm" data-tog="${kind}" data-name="${h(x.name)}">${x.active ? "Απενεργοποίηση" : "Ενεργοποίηση"}</button></div>`).join("")}
    <form class="row-actions" style="margin-top:14px;flex-wrap:nowrap" data-add="${kind}"><input placeholder="Νέο όνομα" required minlength="2" maxlength="120"><button class="btn">Προσθήκη</button></form></div>`;
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Διαχείριση</div><h1>Ρυθμίσεις</h1><p class="muted">Καταστήματα και εταιρείες που εμφανίζονται στις επιλογές.</p></div></div>
  <div class="grid g2">${block("Καταστήματα", "store", S.lists.stores)}${block("Εταιρείες", "company", S.lists.companies)}</div>
  ${specialtiesBlock()}
  ${S.api.mode === "demo" ? "" : `<div class="card" style="margin-top:16px"><div class="card-head"><h3>Πρότυπα κειμένων</h3><a class="btn sm primary" href="#/templates">Άνοιγμα →</a></div><p class="muted small">Κείμενα αιτήσεων, εγκρίσεων, απορρίψεων, διευκρινίσεων, είδη άδειας και λόγοι απόρριψης, με ιστορικό εκδόσεων.</p></div>`}
  <div class="card" style="margin-top:16px"><h3>Πληροφορίες</h3><dl class="kv"><dt>Λειτουργία</dt><dd>${S.api.mode === "demo" ? "Επίδειξη (τοπικά δεδομένα)" : "Σύνδεση με βάση Supabase"}</dd><dt>Έκδοση</dt><dd>2.1 · Καρτέλα εργαζομένου</dd></dl></div>`;
  const reload = async () => { S.lists = await S.api.lists(); settings(); };
  bindSpecialties(reload);
  $$("[data-tog]").forEach((b) => (b.onclick = async () => {
    const arr = b.dataset.tog === "store" ? S.lists.stores : S.lists.companies;
    const x = arr.find((i) => i.name === b.dataset.name);
    try { await (b.dataset.tog === "store" ? S.api.saveStore({ name: x.name, active: !x.active }, false) : S.api.saveCompany({ name: x.name, active: !x.active }, false)); reload(); } catch (e) { toast(e.message, true); }
  }));
  $$("[data-add]").forEach((f) => (f.onsubmit = async (e) => {
    e.preventDefault();
    const name = f.querySelector("input").value.trim();
    const arr = f.dataset.add === "store" ? S.lists.stores : S.lists.companies;
    const rec = { name, sort: arr.length + 1, active: true };
    try { await (f.dataset.add === "store" ? S.api.saveStore(rec, true) : S.api.saveCompany(rec, true)); toast("Προστέθηκε."); reload(); } catch (err) { toast(err.message, true); }
  }));
}

// ═══════════════════════ Backup ═══════════════════════
export async function backup() {
  if (!can.backup()) return (view().innerHTML = `<div class="card empty">Μόνο για τη Γενική Διευθύντρια.</div>`);
  const F = (S.filters.backup ??= { store: "" });
  const list = (await S.api.declarations({ month: S.month, status: "signed" })).filter((d) => !F.store || d.store === F.store);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(monthLabel(S.month))}</div><h1>Μηνιαίο backup</h1>
    <p class="muted">Όλες οι υπογεγραμμένες δηλώσεις του μήνα ως PDF σε φακέλους ανά κατάστημα, μαζί με Excel σύνοψη.</p></div></div>
  <div class="card" style="max-width:680px">
    <label>Κατάστημα</label><select id="bk-store"><option value="">Όλα τα καταστήματα</option>${activeStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>
    <p style="margin-top:16px"><strong>${list.length}</strong> υπογεγραμμένες δηλώσεις για ${h(monthLabel(S.month))}.</p>
    <button class="btn primary block" id="bk-go" ${list.length ? "" : "disabled"}>⇩ Λήψη ZIP με PDF</button>
    <p id="bk-msg" class="muted small" style="margin-top:10px"></p>
  </div>`;
  $("#bk-store").onchange = (e) => { F.store = e.target.value; backup(); };
  $("#bk-go").onclick = async () => {
    const btn = $("#bk-go"); btn.disabled = true;
    try {
      $("#bk-msg").textContent = "Λήψη υπογραφών…";
      const full = await S.api.declarationsFull(list.map((d) => d.id));
      await backupZip(S.month, full, (i, n) => ($("#bk-msg").textContent = `Δημιουργία PDF ${i}/${n}…`));
      $("#bk-msg").textContent = `Έτοιμο: ${full.length} δηλώσεις.`;
    } catch (e) { $("#bk-msg").textContent = "Δεν ολοκληρώθηκε: " + e.message; }
    btn.disabled = false;
  };
}

// ═══════════════════════ Λογαριασμός ═══════════════════════
let installEvt = null;
window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); installEvt = e; });

export async function account() {
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
  const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone;
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Λογαριασμός</div><h1>${h(S.me.name)}</h1><p class="muted">${h(S.me.email)} · ${ROLE_GR[S.me.role]}${S.me.store ? " · " + h(S.me.store) : ""}</p></div>
    <button class="btn" id="ac-out">Αποσύνδεση</button></div>
  <div class="grid g2">
    <div class="card"><h3>Εγκατάσταση στο κινητό / tablet</h3>
      ${standalone ? `<p class="muted" style="margin-top:10px">✓ Η εφαρμογή είναι ήδη εγκατεστημένη σε αυτή τη συσκευή.</p>`
        : ios ? `<p class="muted" style="margin-top:10px;line-height:1.7">Στο Safari πατήστε <strong>Κοινοποίηση</strong> (το τετράγωνο με το βέλος) και μετά <strong>«Προσθήκη στην οθόνη Αφετηρίας»</strong>.</p>`
        : `<p class="muted" style="margin-top:10px">Προσθέστε την εφαρμογή στην αρχική οθόνη για να ανοίγει σαν κανονική εφαρμογή.</p><button class="btn primary" id="ac-install" style="margin-top:14px">⇩ Εγκατάσταση εφαρμογής</button>
           <p class="muted small" style="margin-top:8px">Αν δεν εμφανιστεί παράθυρο: μενού του browser (⋮) → «Εγκατάσταση εφαρμογής» ή «Προσθήκη στην αρχική οθόνη».</p>`}
    </div>
    <div class="card"><h3>Αλλαγή κωδικού</h3><form id="ac-pw"><label>Νέος κωδικός</label><input type="password" id="ac-p1" minlength="8" required autocomplete="new-password"><label>Επανάληψη</label><input type="password" id="ac-p2" minlength="8" required autocomplete="new-password">
      <p id="ac-msg" class="form-msg"></p><button class="btn primary">Αλλαγή κωδικού</button></form></div>
  </div>
  ${S.api.mode === "demo" ? `<div class="card" style="margin-top:16px"><h3>Λειτουργία επίδειξης</h3><p class="muted" style="margin:8px 0 14px">Τα δεδομένα είναι φανταστικά και μένουν μόνο σε αυτόν τον browser.</p><button class="btn danger" id="ac-reset">Επαναφορά δεδομένων επίδειξης</button></div>` : ""}`;
  $("#ac-out").onclick = async () => { await S.api.signOut(); location.hash = ""; location.reload(); };
  $("#ac-install") && ($("#ac-install").onclick = async () => { if (installEvt) { installEvt.prompt(); installEvt = null; } else toast("Χρησιμοποιήστε το μενού του browser → «Εγκατάσταση εφαρμογής»."); });
  $("#ac-pw").onsubmit = async (e) => {
    e.preventDefault();
    if ($("#ac-p1").value !== $("#ac-p2").value) return ($("#ac-msg").textContent = "Οι κωδικοί δεν ταιριάζουν.");
    try { await S.api.changePassword($("#ac-p1").value); $("#ac-msg").className = "form-msg ok"; $("#ac-msg").textContent = "Ο κωδικός άλλαξε."; e.target.reset(); }
    catch (err) { $("#ac-msg").className = "form-msg"; $("#ac-msg").textContent = err.message; }
  };
  $("#ac-reset") && ($("#ac-reset").onclick = () => { S.api.demoReset(); location.reload(); });
}
