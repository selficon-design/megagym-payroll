// Έλεγχος εργαλείων του Βοηθού AI ανά ρόλο, απέναντι στην τοπική βάση (μετά τα e2e_1 και e2e_2).
// node assistant_tools.mjs   (χρειάζεται JWT_SECRET και τον server.mjs σε λειτουργία)
import fs from "node:fs"; import vm from "node:vm"; import crypto from "node:crypto"; import assert from "node:assert/strict";
import { runHrTool } from "../../supabase/functions/_shared/hr-tools.js";
const store = {}; globalThis.window = globalThis; globalThis.localStorage = { getItem: (k) => store[k] ?? null, setItem: (k, v) => (store[k] = v), removeItem: (k) => delete store[k] };
vm.runInThisContext(fs.readFileSync(new URL("./supabase-shim.js", import.meta.url), "utf8"));
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (p) => { const h = b64({ alg: "HS256", typ: "JWT" }), b = b64(p); return `${h}.${b}.${crypto.createHmac("sha256", process.env.JWT_SECRET).update(`${h}.${b}`).digest("base64url")}`; };
const ANON = jwt({ role: "anon", exp: 4102444800 });
const as = (email, role, store = null) => ({ me: { email, role, store }, db: window.supabase.createClient("http://localhost:8787", ANON, { auth: { persistSession: false }, global: { headers: { Authorization: "Bearer " + jwt({ email, role: "authenticated", exp: Math.floor(Date.now() / 1000) + 3600 }) } } }) });
const run = (u, name, input = {}) => runHrTool(u.db, name, input, u.me);
let n = 0; const ok = (c, label) => { assert.ok(c, "ΑΠΟΤΥΧΙΑ: " + label); n++; console.log("  OK", label); };
const owner = as("owner@test.gr", "owner"), hr = as("hr@test.gr", "hr"), gly = as("glyfada@test.gr", "manager", "Γλυφάδα"), kif = as("kifisia@test.gr", "manager", "Κηφισιά"), tr = as("trainer@test.gr", "trainer");
const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Athens" }).format(new Date());
const daysAgo = (d) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10);

// Αιτήματα
let r = await run(owner, "requests_search", { all_statuses: true });
ok(r.count === 3 && r.rows.every((x) => x.ref.startsWith("ΑΙ-")), "ΓΔ: όλα τα αιτήματα (3)");
r = await run(owner, "requests_search", {});
ok(r.rows.some((x) => x.status === "Υποβλήθηκε" && x.leave?.days_requested), "ΓΔ: ανοιχτά αιτήματα με στοιχεία άδειας");
r = await run(kif, "requests_search", { all_statuses: true });
ok(r.count === 0, "manager Κηφισιάς: κανένα αίτημα Γλυφάδας");
r = await run(tr, "requests_search", { all_statuses: true });
ok(r.count === 0, "εκπαιδευτής: κανένα αίτημα");
r = await run(gly, "requests_search", { employee: "δοκιμη", all_statuses: true });
ok(r.count === 2 && r.rows.every((x) => x.employee.includes("T100")), "αναζήτηση εργαζομένου χωρίς τόνους");
r = await run(gly, "request_detail", { ref: "ΑΙ-2026-00001" });
ok(r.decisions.length === 2 && r.decisions.find((d) => d.current).outcome === "Έγκριση" && r.decisions.find((d) => !d.current).reason.includes("Αυξημένες"), "λεπτομέρειες: ισχύουσα απόφαση + αναθεωρημένη με αιτιολογία");
ok(r.hr_internal === undefined && !JSON.stringify(r).includes("base64"), "manager: χωρίς εσωτερικά HR και χωρίς περιεχόμενο συνημμένων");
r = await run(gly, "request_detail", { ref: "ΑΙ-2026-00003" });
ok(r.decisions[0].outcome === "Έγκριση" && r.status === "Ολοκληρώθηκε", "προειδοποίηση: εγκεκριμένη από ΓΔ και κοινοποιημένη");
r = await run(owner, "request_detail", { ref: "ΑΙ-2026-00003" });
ok(r.hr_internal?.warning_draft_exists === true, "ΓΔ: βλέπει ότι υπήρξε προσχέδιο HR");
r = await run(kif, "request_detail", { ref: "ΑΙ-2026-00001" });
ok(r.error, "manager άλλου καταστήματος: το αίτημα «δεν βρέθηκε»");
r = await run(hr, "requests_summary", {});
ok(r.dashboard.needs_my_action === 1 && r.dashboard.approved_awaiting_implementation === 1, "σύνοψη HR: 1 για ενέργειά μου, 1 εγκεκριμένο προς υλοποίηση");
r = await run(gly, "leave_calendar", { from_date: "2026-12-01", to_date: "2026-12-07" });
ok(r.approved.length === 1 && r.approved[0].to === "03/12/2026" && r.approved[0].days == 3, "άδειες: εγκεκριμένες ημερομηνίες (όχι οι αιτούμενες)");
r = await run(gly, "leave_calendar", { from_date: "2027-01-01", to_date: "2027-01-31" });
ok(r.pending.length === 1 && r.approved.length === 0, "άδειες: εκκρεμής αίτηση ξεχωριστά από εγκεκριμένες");

// Στατιστικά
r = await run(hr, "stats_report", { kind: "reception", from_date: daysAgo(25), to_date: today, group_by: "store" });
const sumStores = r.groups.reduce((s, g) => s + g.dr, 0);
ok(r.groups.length === 2 && sumStores === r.overall.dr, "HR: ανά κατάστημα, αθροίσματα συνεπή");
const t = r.overall; ok(t.rates["Συνολική μετατροπή"] === `${(Math.round(((t.dr + t.cb) / t.informed) * 1000) / 10).toString().replace(".", ",")}%`, "μετατροπή από αθροίσματα (ΣDR+ΣCB)/ΣΕνημερώσεις");
r = await run(kif, "stats_report", { kind: "reception", from_date: daysAgo(25), to_date: today, group_by: "store" });
ok(r.groups.length === 1 && r.groups[0].store === "Κηφισιά", "manager: στατιστικά μόνο του καταστήματός του");
r = await run(tr, "stats_report", { kind: "reception", from_date: daysAgo(25), to_date: today });
ok(r.overall.entries === 0, "εκπαιδευτής: κανένα στατιστικό");
r = await run(gly, "stats_report", { kind: "exclusive", from_date: today, to_date: today, group_by: "employee" });
ok(r.groups[0].rates["Μετατροπή δοκιμαστικών"] === "—", "μηδενικός παρονομαστής → «—»");
r = await run(gly, "missing_stats", { date: daysAgo(1) });
ok(r.missing.some((m) => m.employee.includes("T100")) && r.without_specialty.some((x) => x.includes("T201")), "χωρίς καταχώριση χθες + εργαζόμενοι χωρίς ειδικότητα");

// Αξιολογήσεις
r = await run(hr, "assessment_results", {});
ok(r.rows.some((x) => x.result.startsWith("6 / 11")) && Object.values(r.average_per_version)[0].startsWith("54,5%"), "HR: βαθμοί και μέσος όρος ανά έκδοση");
ok(r.rows.some((x) => x.state === "Δεν ξεκίνησε"), "HR: και όσοι δεν ξεκίνησαν");
r = await run(gly, "assessment_results", {});
ok(r.note && !JSON.stringify(r).includes("/ 11") && r.rows.every((x) => x.store === "Γλυφάδα"), "manager: μόνο κατάσταση, χωρίς βαθμούς, μόνο το κατάστημά του");
r = await run(gly, "assessments_overview", {});
ok(r.count === 1 && r.questionnaires[0].employees_in_your_scope, "manager: επισκόπηση ενεργών ερωτηματολογίων");
r = await run(owner, "assessments_overview", { title: "ρεσεψιον" });
ok(r.count === 1 && r.questionnaires[0].active_version === 1, "ΓΔ: αναζήτηση τίτλου χωρίς τόνους");
console.log(`\n✓ ${n} έλεγχοι εργαλείων Βοηθού`);
