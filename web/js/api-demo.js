// Λειτουργία επίδειξης: ίδια συμπεριφορά με τη βάση, αλλά τα δεδομένα μένουν μόνο σε αυτόν τον browser.
// Όλα τα ονόματα είναι φανταστικά.
import { currentMonth, shiftMonth, monthBounds, defaultPeriod, statementText, parseAmount, norm } from "./util.js";

const KEY = "mega-payroll-demo-v1";
const STORES = ["Αγία Παρασκευή", "Βριλήσσια - Μελίσσια", "Γλυφάδα", "Κηφισιά", "Μεταμόρφωση", "Άλιμος", "Γέρακας", "Νέα Ιωνία"];
const COMPANIES = ["ΥΠΟΣΤΗΡΙΞΗ ΓΥΜΝΑΣΤΗΡΙΩΝ ΑΕ", "ARG BEST GREEK GYMS IKE", "BEST GREEK GYMS IKE", "IONIA BEST GREEK GYMS IKE"];
const MALE = ["Γιώργος", "Νίκος", "Κώστας", "Δημήτρης", "Γιάννης", "Παναγιώτης", "Αλέξανδρος", "Σταύρος", "Μιχάλης", "Θανάσης"];
const FEMALE = ["Μαρία", "Ελένη", "Κατερίνα", "Σοφία", "Δέσποινα", "Χριστίνα", "Ιωάννα", "Αθηνά", "Βασιλική", "Φωτεινή"];
const LAST_M = ["Παπαδόπουλος", "Οικονόμου", "Αντωνίου", "Δημητρίου", "Βασιλείου", "Ζαχαρίου", "Μαυρίδης", "Λαμπράκης", "Σταματίου", "Πετρίδης", "Χατζής", "Καραγιάννης"];
const LAST_F = ["Παπαδοπούλου", "Οικονόμου", "Αντωνίου", "Δημητρίου", "Βασιλείου", "Ζαχαρίου", "Μαυρίδου", "Λαμπράκη", "Σταματίου", "Πετρίδου", "Χατζή", "Καραγιάννη"];
const USERS = [
  { email: "owner@demo.gr", name: "Γενική Διευθύντρια (επίδειξη)", role: "owner", store: null, active: true },
  { email: "hr@demo.gr", name: "Τμήμα HR (επίδειξη)", role: "hr", store: null, active: true },
  { email: "glyfada@demo.gr", name: "Manager Γλυφάδας (επίδειξη)", role: "manager", store: "Γλυφάδα", active: true },
  { email: "kifisia@demo.gr", name: "Manager Κηφισιάς (επίδειξη)", role: "manager", store: "Κηφισιά", active: true },
];

let rnd = 7;
const rand = () => ((rnd = (rnd * 16807) % 2147483647) / 2147483647);
const pick = (a) => a[Math.floor(rand() * a.length)];
const uuid = () => crypto.randomUUID ? crypto.randomUUID() : String(Date.now() + Math.random());

function fakeSignature(name) {
  const c = document.createElement("canvas"); c.width = 420; c.height = 130;
  const x = c.getContext("2d"); x.fillStyle = "#fff"; x.fillRect(0, 0, 420, 130);
  x.strokeStyle = "#0e1a2b"; x.lineWidth = 2.6; x.lineCap = "round"; x.beginPath();
  let px = 30, py = 80; x.moveTo(px, py);
  for (let i = 0; i < 26; i++) { px += 12 + rand() * 6; py = 65 + Math.sin(i * 1.3 + name.length) * 28 * rand(); x.quadraticCurveTo(px - 6, py - 30 * rand(), px, py); }
  x.stroke();
  return c.toDataURL("image/png");
}

function seed() {
  const employees = [];
  let n = 1001;
  for (const store of STORES) {
    const count = 5 + Math.floor(rand() * 4);
    for (let i = 0; i < count; i++) {
      const fem = rand() < 0.5;
      employees.push({ code: "MG" + n++, first: pick(fem ? FEMALE : MALE), last: pick(fem ? LAST_F : LAST_M), store, company: pick(COMPANIES), status: rand() > 0.08 ? "Ενεργός" : "Ανενεργός" });
    }
  }
  const declarations = [], audit = [];
  const cur = currentMonth(), prev = shiftMonth(cur, -1), prev2 = shiftMonth(cur, -2);
  const sig = fakeSignature("demo");
  for (const [m, signedShare, preparedShare] of [[prev2, 1, 1], [prev, 0.93, 1], [cur, 0.35, 0.7]]) {
    const b = monthBounds(m);
    for (const e of employees.filter((x) => x.status === "Ενεργός")) {
      if (rand() > preparedShare) continue;
      const amount = Math.round((650 + rand() * 900) * 100) / 100;
      const period = defaultPeriod(m);
      const signed = rand() < signedShare;
      const day = Math.min(28, 1 + Math.floor(rand() * 10));
      const signedAt = new Date(Number(m.slice(0, 4)), Number(m.slice(5)), day, 9 + Math.floor(rand() * 9), Math.floor(rand() * 59));
      const d = {
        id: uuid(), employee_code: e.code, employee_name: `${e.first} ${e.last}`, store: e.store, company: e.company,
        month: m, end_date: b.last, period, amount, status: signed ? "signed" : "pending",
        statement: signed ? statementText(e.company, b.last, period, amount) : null,
        signer: signed ? `${e.first} ${e.last}` : null, signature: signed ? sig : null,
        signed_at: signed ? (signedAt > new Date() ? new Date(Date.now() - rand() * 86400000 * 3) : signedAt).toISOString() : null,
        signed_by: signed ? (e.store === "Γλυφάδα" ? "glyfada@demo.gr" : "owner@demo.gr") : null,
        prepared_by: "hr@demo.gr", prepared_at: new Date(Date.now() - 86400000 * 5).toISOString(),
      };
      declarations.push(d);
      if (signed) audit.push({ id: audit.length + 1, at: d.signed_at, actor: d.signed_by, action: "sign", entity: "declarations", entity_id: d.id, details: { label: d.employee_name, month: m, store: d.store } });
    }
  }
  audit.sort((a, b) => (a.at < b.at ? 1 : -1));
  return {
    stores: STORES.map((name, i) => ({ name, sort: i + 1, active: true })),
    companies: COMPANIES.map((name, i) => ({ name, sort: i + 1, active: true })),
    users: USERS, employees, declarations, audit, as: "owner@demo.gr", signedIn: false,
  };
}

export function createDemoApi() {
  let S;
  try { S = JSON.parse(localStorage.getItem(KEY)); } catch {}
  if (!S) S = seed();
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch {} };
  const me = () => S.users.find((u) => u.email === S.as && u.active);
  const role = () => me()?.role;
  const canSee = (store) => role() === "owner" || role() === "hr" || (role() === "manager" && me().store === store);
  const deny = () => { throw new Error("Δεν έχετε δικαίωμα για αυτή την ενέργεια."); };
  const wait = (v) => new Promise((r) => setTimeout(() => r(structuredClone(v)), 120));
  const log = (action, entity, entity_id, details) => {
    S.audit.unshift({ id: Date.now() + Math.random(), at: new Date().toISOString(), actor: S.as, action, entity, entity_id, details });
  };
  const strip = ({ signature, statement, ...rest }) => rest;

  return {
    mode: "demo",
    demoUsers: () => S.users.filter((u) => u.active),
    demoAs: () => S.as,
    demoSwitch(email) { S.as = email; save(); },
    demoReset() { localStorage.removeItem(KEY); },
    onAuthChange() {},
    async session() { return S.signedIn && me() ? wait({ email: me().email, name: me().name, role: me().role, store: me().store }) : null; },
    async signIn(email) {
      const u = S.users.find((x) => x.email === String(email).trim().toLowerCase());
      if (u) S.as = u.email;
      S.signedIn = true; save();
    },
    async signOut() { S.signedIn = false; save(); },
    async verifyPassword(pw) { if (!pw) throw new Error("Λάθος κωδικός."); },
    async changePassword() {},

    async lists() { if (!role()) deny(); return wait({ stores: S.stores, companies: S.companies }); },
    async saveStore(s, isNew) {
      if (role() !== "owner") deny();
      if (isNew) { if (S.stores.some((x) => x.name === s.name)) throw new Error("Υπάρχει ήδη."); S.stores.push({ sort: 99, active: true, ...s }); }
      else Object.assign(S.stores.find((x) => x.name === s.name), s);
      log(isNew ? "insert" : "update", "stores", s.name, s); save();
    },
    async saveCompany(c, isNew) {
      if (role() !== "owner") deny();
      if (isNew) { if (S.companies.some((x) => x.name === c.name)) throw new Error("Υπάρχει ήδη."); S.companies.push({ sort: 99, active: true, ...c }); }
      else Object.assign(S.companies.find((x) => x.name === c.name), c);
      log(isNew ? "insert" : "update", "companies", c.name, c); save();
    },

    async employees() { return wait(S.employees.filter((e) => canSee(e.store)).sort((a, b) => a.last.localeCompare(b.last, "el"))); },
    async saveEmployee(e, isNew) {
      if (!["owner", "hr"].includes(role())) deny();
      const ex = S.employees.find((x) => x.code === e.code);
      if (isNew && ex) throw new Error("Υπάρχει ήδη εγγραφή με αυτά τα στοιχεία.");
      if (isNew) S.employees.push(e); else Object.assign(ex, e);
      log(isNew ? "insert" : "update", "employees", e.code, { label: `${e.first} ${e.last}`, store: e.store });
      save();
    },
    async importEmployees(rows) {
      if (!["owner", "hr"].includes(role())) deny();
      for (const r of rows) { const ex = S.employees.find((x) => x.code === r.code); if (ex) Object.assign(ex, r); else S.employees.push(r); }
      log("import", "employees", null, { count: rows.length }); save();
      return rows.length;
    },

    async monthStatus(month) {
      const rows = S.employees.filter((e) => canSee(e.store)).map((e) => {
        const d = S.declarations.find((x) => x.employee_code === e.code && x.month === month && x.status !== "voided");
        if (e.status !== "Ενεργός" && !d) return null;
        return { code: e.code, first: e.first, last: e.last, store: e.store, company: e.company, emp_status: e.status,
          declaration_id: d?.id ?? null, status: d?.status ?? "missing", amount: d?.amount ?? null, period: d?.period ?? null,
          end_date: d?.end_date ?? null, signed_at: d?.signed_at ?? null, signer: d?.signer ?? null, prepared_at: d?.prepared_at ?? null };
      }).filter(Boolean);
      return wait(rows.sort((a, b) => a.store.localeCompare(b.store, "el") || a.last.localeCompare(b.last, "el")));
    },
    async declarations({ month, status, store } = {}) {
      return wait(S.declarations.filter((d) => canSee(d.store) && (!month || d.month === month) && (!status || d.status === status) && (!store || d.store === store))
        .sort((a, b) => (b.month + (b.signed_at || "")).localeCompare(a.month + (a.signed_at || ""))).map(strip));
    },
    async declaration(id) { const d = S.declarations.find((x) => x.id === id && canSee(x.store)); if (!d) throw new Error("Η δήλωση δεν βρέθηκε."); return wait(d); },
    async declarationsFull(ids) { return wait(S.declarations.filter((d) => ids.includes(d.id) && canSee(d.store))); },
    async prepare(month, rows) {
      const r0 = role(); if (!r0) deny();
      const b = monthBounds(month);
      let created = 0, updated = 0; const skipped = [];
      for (const r of rows) {
        const e = S.employees.find((x) => x.code === String(r.code).trim());
        if (!e) { skipped.push({ code: r.code, reason: "Άγνωστος κωδικός" }); continue; }
        if (e.status !== "Ενεργός") { skipped.push({ code: e.code, reason: "Ανενεργός εργαζόμενος" }); continue; }
        if (r0 === "manager" && e.store !== me().store) { skipped.push({ code: e.code, reason: "Άλλο κατάστημα" }); continue; }
        const amount = parseAmount(r.amount);
        if (amount === null) { skipped.push({ code: e.code, reason: "Μη έγκυρο ποσό" }); continue; }
        const period = (r.period || "").trim() || defaultPeriod(month);
        const end_date = r.end_date || b.last;
        const d = S.declarations.find((x) => x.employee_code === e.code && x.month === month && x.status !== "voided");
        if (d) {
          if (d.status === "signed") { skipped.push({ code: e.code, reason: "Έχει ήδη υπογράψει" }); continue; }
          Object.assign(d, { amount, period, end_date, prepared_by: S.as, prepared_at: new Date().toISOString() }); updated++;
          log("update", "declarations", d.id, { label: d.employee_name, month, store: d.store });
        } else {
          const nd = { id: uuid(), employee_code: e.code, employee_name: `${e.first} ${e.last}`, store: e.store, company: e.company, month, end_date, period, amount, status: "pending", prepared_by: S.as, prepared_at: new Date().toISOString() };
          S.declarations.push(nd); created++;
          log("insert", "declarations", nd.id, { employee_name: nd.employee_name, month, store: nd.store, amount });
        }
      }
      save();
      return wait({ created, updated, skipped });
    },
    async sign(id, signer, signature) {
      if (!["owner", "manager"].includes(role())) throw new Error("Δεν επιτρέπεται η υπογραφή από αυτόν τον λογαριασμό.");
      const d = S.declarations.find((x) => x.id === id);
      if (!d) throw new Error("Η δήλωση δεν βρέθηκε.");
      if (role() === "manager" && d.store !== me().store) throw new Error("Η δήλωση ανήκει σε άλλο κατάστημα.");
      if (d.status !== "pending") throw new Error("Η δήλωση έχει ήδη υπογραφεί ή ακυρωθεί.");
      if (String(signer || "").trim().length < 3) throw new Error("Συμπληρώστε ονοματεπώνυμο.");
      Object.assign(d, { status: "signed", statement: statementText(d.company, d.end_date, d.period, d.amount), signer: signer.trim(), signature, signed_at: new Date().toISOString(), signed_by: S.as, device: navigator.userAgent.slice(0, 300) });
      log("sign", "declarations", d.id, { label: d.employee_name, month: d.month, store: d.store });
      save();
      return { ok: true };
    },
    async voidDeclaration(id, reason) {
      if (role() !== "owner") throw new Error("Μόνο η Γενική Διευθύντρια μπορεί να ακυρώσει δήλωση.");
      const d = S.declarations.find((x) => x.id === id);
      Object.assign(d, { status: "voided", voided_by: S.as, voided_at: new Date().toISOString(), void_reason: reason });
      log("void", "declarations", d.id, { label: d.employee_name, month: d.month, store: d.store }); save();
    },
    async discardPending(id) {
      const d = S.declarations.find((x) => x.id === id);
      if (!d || d.status !== "pending") throw new Error("Μόνο δηλώσεις προς υπογραφή μπορούν να αφαιρεθούν.");
      if (!(["owner", "hr"].includes(role()) || (role() === "manager" && d.store === me().store))) deny();
      Object.assign(d, { status: "voided", voided_by: S.as, voided_at: new Date().toISOString(), void_reason: "Αφαίρεση προετοιμασμένης δήλωσης" });
      log("void", "declarations", d.id, { label: d.employee_name, month: d.month, store: d.store }); save();
    },

    async users() { if (role() !== "owner") return wait(S.users.filter((u) => u.email === S.as)); return wait(S.users); },
    async userStatuses() { return Object.fromEntries(S.users.map((u) => [u.email, { hasLogin: true, locked: !u.active, lastSignIn: null }])); },
    async saveUser(u) {
      if (role() !== "owner") deny();
      const ex = S.users.find((x) => x.email === u.email);
      if (ex) Object.assign(ex, u); else S.users.push({ active: true, ...u });
      log(ex ? "update" : "insert", "app_users", u.email, { name: u.name, role: u.role, store: u.store }); save();
    },
    async setPassword() {},
    async setActive(email, active) {
      if (role() !== "owner") deny();
      const u = S.users.find((x) => x.email === email);
      if (!active && u.role === "owner" && S.users.filter((x) => x.role === "owner" && x.active).length < 2) throw new Error("Πρέπει να υπάρχει τουλάχιστον μία ενεργή Γενική Διευθύντρια.");
      u.active = active; log("update", "app_users", email, { changes: { active: { to: active } } }); save();
    },
    async deleteUser(email) {
      if (role() !== "owner") deny();
      if (email === S.as) throw new Error("Δεν μπορείτε να διαγράψετε τον εαυτό σας.");
      S.users = S.users.filter((x) => x.email !== email); log("delete", "app_users", email, {}); save();
    },

    async audit({ limit = 200, entity } = {}) {
      if (!["owner", "hr"].includes(role())) return [];
      return wait(S.audit.filter((a) => !entity || a.entity === entity).slice(0, limit));
    },

    async ask(messages) {
      const q = norm(messages[messages.length - 1].content);
      const month = currentMonth();
      const rows = await this.monthStatus(month);
      const miss = rows.filter((r) => r.status !== "signed");
      await new Promise((r) => setTimeout(r, 600));
      const head = "_(Λειτουργία επίδειξης: εδώ δείχνω ένα απλό δείγμα. Όταν συνδεθεί η βάση και το κλειδί AI, ο Βοηθός καταλαβαίνει ελεύθερες ερωτήσεις και ψάχνει σε όλα τα δεδομένα.)_\n\n";
      if (q.includes("υπογρα") || q.includes("λειπ") || q.includes("εκκρεμ")) {
        return head + `Για τον τρέχοντα μήνα λείπουν **${miss.length}** υπογραφές:\n` + miss.slice(0, 15).map((r) => `- ${r.first} ${r.last} · ${r.store} · ${r.status === "pending" ? "προς υπογραφή" : "χωρίς δήλωση"}`).join("\n") + (miss.length > 15 ? `\n…και ${miss.length - 15} ακόμη.` : "");
      }
      const by = {};
      for (const r of rows) { const s = (by[r.store] ??= { s: 0, t: 0 }); s.t++; if (r.status === "signed") s.s++; }
      return head + `Σύνοψη τρέχοντος μήνα ανά κατάστημα:\n` + Object.entries(by).map(([k, v]) => `- **${k}**: ${v.s}/${v.t} υπογεγραμμένες`).join("\n");
    },
  };
}
