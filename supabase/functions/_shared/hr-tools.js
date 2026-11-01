// Εργαλεία του Βοηθού AI για τις ενότητες της καρτέλας εργαζομένου:
// αιτήματα & αναφορές, άδειες, ημερήσια στατιστικά, αξιολογήσεις.
// ΚΑΘΕ ερώτημα τρέχει με τα δικαιώματα του χρήστη που ρωτά (RLS): ο manager παίρνει μόνο το κατάστημά του,
// βαθμοί/απαντήσεις αξιολογήσεων φτάνουν μόνο σε ΓΔ/HR. Δεν διαβάζονται ποτέ: συνημμένα, υπογραφές,
// κλειδιά φορμών, σωστές απαντήσεις ερωτηματολογίων, αναλυτικές απαντήσεις εργαζομένων.
// Απλό JavaScript ώστε να ελέγχεται και τοπικά (tests/e2e/assistant_tools.mjs).
import { KINDS, totals, metrics, warnings, daysBetween } from "./stats-calc.js";

export const CATEGORY_GR = {
  leave: "Άδεια / απουσία", shift_change: "Αλλαγή βάρδιας, ρεπό ή προγράμματος", raise: "Αύξηση αποδοχών",
  contract_change: "Αλλαγή ωρών ή σύμβασης", advance: "Προκαταβολή", documents: "Βεβαιώσεις και έγγραφα",
  transfer: "Μετακίνηση καταστήματος ή αλλαγή θέσης", other_hr: "Λοιπό αίτημα προς HR",
  negative_review: "Αρνητική αξιολόγηση (αναφορά manager)", incident: "Περιστατικό (αναφορά manager)",
  warning_request: "Αίτημα έγγραφης προειδοποίησης (αναφορά manager)",
};
export const REQ_STATUS_GR = {
  draft: "Πρόχειρο", submitted: "Υποβλήθηκε", under_review: "Σε εξέταση", needs_info: "Απαιτούνται διευκρινίσεις",
  awaiting_gm: "Αναμονή έγκρισης ΓΔ", approved: "Εγκρίθηκε", rejected: "Απορρίφθηκε", completed: "Ολοκληρώθηκε",
};
const OUTCOME_GR = { approve: "Έγκριση", reject: "Απόρριψη", needs_info: "Απαιτούνται διευκρινίσεις" };
const ATTEMPT_GR = { not_started: "Δεν ξεκίνησε", in_progress: "Σε εξέλιξη", submitted: "Υποβλήθηκε", pending_manual: "Αναμένει χειροκίνητη βαθμολόγηση", expired: "Έληξε χωρίς υποβολή" };
const OPEN = ["submitted", "under_review", "needs_info", "awaiting_gm", "approved"];
const STATUS_KEYS = Object.keys(REQ_STATUS_GR);
const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(String(s || ""));
const norm = (s) => String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
const pct = (v) => (v === null || v === undefined || !isFinite(v) ? "—" : `${(Math.round(v * 10) / 10).toString().replace(".", ",")}%`);
const who = (x) => (!x ? null : String(x).startsWith("employee:") ? "ο ίδιος ο εργαζόμενος" : x);
const athens = (ts) => (ts ? new Date(ts).toLocaleString("el-GR", { timeZone: "Europe/Athens", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : null);
const dmy = (d) => (d ? String(d).slice(0, 10).split("-").reverse().join("/") : null);
const athensToday = () => {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Athens", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date()).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day}`;
};
async function all(build, max = 20000) {
  const out = [];
  for (let from = 0; from < max; from += 1000) {
    const { data, error } = await build().range(from, from + 999);
    if (error) throw new Error(error.message);
    out.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  return out;
}
const matchesEmployee = (q) => { const parts = norm(q).split(/\s+/).filter(Boolean); return (name, code) => parts.every((p) => norm(`${name} ${code}`).includes(p)); };

export const hrTools = [
  {
    name: "requests_search",
    description: "Αναζήτηση αιτημάτων εργαζομένων και αναφορών manager. Επιστρέφει αριθμό αιτήματος, εργαζόμενο, κατάστημα, κατηγορία, κατάσταση, ημερομηνίες, υπεύθυνο, ισχύουσα απόφαση και αν ενημερώθηκε ο εργαζόμενος. Χωρίς φίλτρο κατάστασης επιστρέφει τα ανοιχτά (υποβλήθηκε, σε εξέταση, διευκρινίσεις, αναμονή ΓΔ, εγκρίθηκε χωρίς υλοποίηση).",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "array", items: { type: "string", enum: STATUS_KEYS }, description: "Καταστάσεις· κενό = ανοιχτά" },
        all_statuses: { type: "boolean", description: "true = όλες οι καταστάσεις" },
        category: { type: "string", enum: Object.keys(CATEGORY_GR) },
        store: { type: "string" },
        employee: { type: "string", description: "Όνομα, επώνυμο ή κωδικός εργαζομένου" },
        from_date: { type: "string", description: "YYYY-MM-DD (ημερομηνία υποβολής ή δημιουργίας)" },
        to_date: { type: "string", description: "YYYY-MM-DD, συμπεριλαμβάνεται" },
        assignee: { type: "string", description: "email υπευθύνου ή «none» για χωρίς υπεύθυνο" },
        not_notified: { type: "boolean", description: "μόνο αποφάσεις που δεν έχουν γνωστοποιηθεί στον εργαζόμενο" },
      },
    },
  },
  {
    name: "request_detail",
    description: "Πλήρης εικόνα ενός αιτήματος με τον αριθμό του (π.χ. ΑΙ-2026-00012): κείμενο, πεδία άδειας ή αναφοράς, ποιος το διατύπωσε/συμπλήρωσε/υπέβαλε, όλες οι αποφάσεις (και όσες αναθεωρήθηκαν) με αιτιολογία, και ιστορικό ενεργειών.",
    input_schema: { type: "object", properties: { ref: { type: "string" } }, required: ["ref"] },
  },
  {
    name: "requests_summary",
    description: "Σύνοψη αιτημάτων: πλήθος ανά κατάσταση, κατηγορία και κατάστημα, και οι τρεις ομάδες του πίνακα: «χρειάζονται ενέργεια του χρήστη», «εκκρεμούν στο HR», «εγκρίθηκαν — αναμένεται υλοποίηση».",
    input_schema: { type: "object", properties: { from_date: { type: "string" }, to_date: { type: "string" }, store: { type: "string" } } },
  },
  {
    name: "leave_calendar",
    description: "Ποιοι έχουν εγκεκριμένη άδεια (με τις εγκεκριμένες ημερομηνίες) ή εκκρεμή αίτηση άδειας που επικαλύπτει ένα διάστημα. Δεν υπάρχει υπόλοιπο άδειας στο σύστημα.",
    input_schema: {
      type: "object",
      properties: { from_date: { type: "string" }, to_date: { type: "string" }, store: { type: "string" }, include_pending: { type: "boolean" } },
      required: ["from_date", "to_date"],
    },
  },
  {
    name: "stats_report",
    description: "Ημερήσια στατιστικά για διάστημα (από–έως, συμπεριλαμβάνονται και οι δύο). Μία ειδικότητα τη φορά: reception (Ρεσεψιόν), supervision (Επίβλεψη), exclusive. Αθροίσματα αρχικών μεγεθών και ποσοστά ΑΠΟ ΤΑ ΑΘΡΟΙΣΜΑΤΑ, ανά εργαζόμενο, κατάστημα ή ημέρα, με προειδοποιήσεις ασυμφωνίας και ημέρες χωρίς καταχώριση.",
    input_schema: {
      type: "object",
      properties: {
        kind: { type: "string", enum: ["reception", "supervision", "exclusive"] },
        from_date: { type: "string" }, to_date: { type: "string" },
        store: { type: "string" }, employee: { type: "string" },
        group_by: { type: "string", enum: ["employee", "store", "day", "none"] },
      },
      required: ["kind", "from_date", "to_date"],
    },
  },
  {
    name: "missing_stats",
    description: "Ποιοι εργαζόμενοι με ειδικότητα στατιστικών ΔΕΝ έχουν καταχώριση για μια ημερομηνία (η έλλειψη καταχώρισης διαφέρει από το μηδέν).",
    input_schema: { type: "object", properties: { date: { type: "string" }, store: { type: "string" } }, required: ["date"] },
  },
  {
    name: "assessments_overview",
    description: "Ερωτηματολόγια αξιολόγησης: τίτλος, κατάσταση, διάστημα διαθεσιμότητας (ώρα Ελλάδας), ειδικότητες και πόσοι εργαζόμενοι του πεδίου του χρήστη δεν ξεκίνησαν, είναι σε εξέλιξη, υπέβαλαν, έληξαν ή αναμένουν βαθμολόγηση.",
    input_schema: { type: "object", properties: { title: { type: "string", description: "μέρος του τίτλου (προαιρετικό)" } } },
  },
  {
    name: "assessment_results",
    description: "Αποτελέσματα αξιολογήσεων ανά εργαζόμενο (κατάσταση, έκδοση ερωτηματολογίου, βαθμοί/μέγιστο, %). Βαθμούς βλέπουν μόνο η ΓΔ και το HR· για τους άλλους ρόλους επιστρέφεται μόνο η κατάσταση. Οι βαθμοί συγκρίνονται μόνο μέσα στην ίδια έκδοση.",
    input_schema: {
      type: "object",
      properties: { title: { type: "string" }, employee: { type: "string" }, store: { type: "string" }, specialty: { type: "string" }, state: { type: "string", enum: Object.keys(ATTEMPT_GR) } },
    },
  },
];

export async function runHrTool(db, name, input, me) {
  switch (name) {
    case "requests_search": {
      const rows0 = await all(() => {
        let q = db.from("hr_requests").select("id,ref,process,category,employee_code,employee_name,store,specialty,status,entry_mode,created_by,created_at,submitted_at,assignee,leave_type_label,start_date,end_date,days_requested,incident_date,notified_at,completed_at").order("created_at", { ascending: false });
        if (input.category) q = q.eq("category", input.category);
        if (input.store) q = q.eq("store", input.store);
        return q;
      });
      const emp = input.employee ? matchesEmployee(input.employee) : null;
      const statuses = input.all_statuses ? null : Array.isArray(input.status) && input.status.length ? input.status : OPEN;
      const rows = rows0.filter((r) =>
        (r.status !== "draft" || r.created_by === me.email) &&
        (!statuses || statuses.includes(r.status)) &&
        (!emp || emp(r.employee_name, r.employee_code)) &&
        (!isDate(input.from_date) || (r.submitted_at || r.created_at).slice(0, 10) >= input.from_date) &&
        (!isDate(input.to_date) || (r.submitted_at || r.created_at).slice(0, 10) <= input.to_date) &&
        (!input.assignee || (input.assignee === "none" ? !r.assignee : r.assignee === input.assignee)) &&
        (!input.not_notified || (["approved", "rejected", "needs_info"].includes(r.status) && !r.notified_at && r.category !== "warning_request")));
      const ids = rows.slice(0, 200).map((r) => r.id);
      const dec = ids.length ? await all(() => db.from("hr_decisions").select("request_id,outcome,decided_by,decided_at,approved_start,approved_end,approved_days,reason_label").in("request_id", ids).is("superseded_at", null)) : [];
      const D = Object.fromEntries(dec.map((d) => [d.request_id, d]));
      return {
        count: rows.length, truncated: rows.length > 200,
        rows: rows.slice(0, 200).map((r) => ({
          ref: r.ref, type: r.process === "manager" ? "Αναφορά manager" : "Αίτημα εργαζομένου", category: CATEGORY_GR[r.category],
          employee: `${r.employee_name} (${r.employee_code})`, store: r.store, status: REQ_STATUS_GR[r.status],
          submitted: athens(r.submitted_at), assignee: r.assignee,
          leave: r.category === "leave" ? { type: r.leave_type_label, from: dmy(r.start_date), to: dmy(r.end_date), days_requested: r.days_requested } : undefined,
          incident_date: dmy(r.incident_date) || undefined,
          decision: D[r.id] ? { outcome: OUTCOME_GR[D[r.id].outcome], by: D[r.id].decided_by, at: athens(D[r.id].decided_at), approved: D[r.id].approved_start ? `${dmy(D[r.id].approved_start)} – ${dmy(D[r.id].approved_end)}, ${D[r.id].approved_days} ημέρες` : undefined, reason: D[r.id].reason_label || undefined } : null,
          employee_notified: r.notified_at ? athens(r.notified_at) : null, completed: athens(r.completed_at),
        })),
      };
    }
    case "request_detail": {
      const ref = String(input.ref || "").trim().toUpperCase().replace(/^AI-/, "ΑΙ-");
      const { data: r, error } = await db.from("hr_requests").select("*").eq("ref", ref).maybeSingle();
      if (error) return { error: error.message };
      if (!r || (r.status === "draft" && r.created_by !== me.email)) return { error: "Δεν βρέθηκε αίτημα με αυτόν τον αριθμό στο πεδίο σας." };
      const [{ data: decisions }, { data: events }, { data: atts }, { data: internal }] = await Promise.all([
        db.from("hr_decisions").select("outcome,decided_by,decided_role,decided_at,reason_label,reason_text,message,approved_start,approved_end,approved_days,alternative,info_requested,superseded_at,is_revision").eq("request_id", r.id).order("decided_at"),
        db.from("hr_request_events").select("at,actor,action,to_status,note").eq("request_id", r.id).order("at"),
        db.from("hr_attachments").select("filename").eq("request_id", r.id),
        db.from("hr_request_internal").select("hr_note,warning_draft").eq("request_id", r.id).maybeSingle(),
      ]);
      return {
        ref: r.ref, type: r.process === "manager" ? "Αναφορά manager" : "Αίτημα εργαζομένου", category: CATEGORY_GR[r.category],
        employee: `${r.employee_name} (${r.employee_code})`, store_at_the_time: r.store, specialty_at_the_time: r.specialty, status: REQ_STATUS_GR[r.status],
        stated_by: who(r.stated_by), written_by: who(r.written_by), submitted_by: r.submitted_by, submitted_at: athens(r.submitted_at), assignee: r.assignee,
        text: r.body, leave: r.category === "leave" ? { type: r.leave_type_label, from: dmy(r.start_date), to: dmy(r.end_date), days_requested: r.days_requested } : undefined,
        report: r.process === "manager" ? { incident_date: dmy(r.incident_date), ...r.details } : undefined,
        notes: r.details?.notes || r.details?.subject || undefined, manager_note: r.manager_note,
        hr_internal: internal ? { hr_note: internal.hr_note, warning_draft_exists: !!internal.warning_draft } : undefined,
        attachments: (atts || []).map((a) => a.filename),
        decisions: (decisions || []).map((d) => ({ outcome: OUTCOME_GR[d.outcome], current: !d.superseded_at, revision: d.is_revision, by: `${d.decided_by} (${d.decided_role === "owner" ? "ΓΔ" : "HR"})`, at: athens(d.decided_at), reason: d.reason_label ? `${d.reason_label}: ${d.reason_text}` : undefined, approved: d.approved_start ? `${dmy(d.approved_start)} – ${dmy(d.approved_end)}, ${d.approved_days} ημέρες` : undefined, alternative: d.alternative || undefined, info_requested: d.info_requested || undefined, message: d.message })),
        employee_notified: athens(r.notified_at), completed: r.completed_at ? `${athens(r.completed_at)} — ${r.completion_note}` : null,
        history: (events || []).map((e) => ({ at: athens(e.at), by: who(e.actor), action: e.action, to: REQ_STATUS_GR[e.to_status] || undefined, note: e.note || undefined })),
      };
    }
    case "requests_summary": {
      const rows0 = await all(() => { let q = db.from("hr_requests").select("category,store,status,assignee,created_by,submitted_at,created_at,notified_at"); if (input.store) q = q.eq("store", input.store); return q; });
      const rows = rows0.filter((r) => (r.status !== "draft" || r.created_by === me.email) &&
        (!isDate(input.from_date) || (r.submitted_at || r.created_at).slice(0, 10) >= input.from_date) &&
        (!isDate(input.to_date) || (r.submitted_at || r.created_at).slice(0, 10) <= input.to_date));
      const count = (key, label) => { const o = {}; for (const r of rows) { const k = label ? label[r[key]] : r[key]; o[k] = (o[k] || 0) + 1; } return o; };
      const flow = (c) => (c === "leave" ? "leave" : ["raise", "contract_change"].includes(c) ? "gm" : c === "warning_request" ? "warning" : ["negative_review", "incident"].includes(c) ? "report" : "generic");
      const mine = rows.filter((x) => {
        if (me.role === "owner") return x.status === "awaiting_gm" || (["leave", "generic"].includes(flow(x.category)) && ["submitted", "under_review"].includes(x.status));
        if (me.role === "hr") return ["submitted", "under_review"].includes(x.status) && (!x.assignee || x.assignee === me.email);
        return x.status === "needs_info" || (x.status === "draft" && x.created_by === me.email) || (["approved", "rejected"].includes(x.status) && !x.notified_at && x.category !== "warning_request");
      }).length;
      return {
        total: rows.length, by_status: count("status", REQ_STATUS_GR), by_category: count("category", CATEGORY_GR), by_store: count("store"),
        dashboard: { needs_my_action: mine, pending_at_hr: rows.filter((r) => ["submitted", "under_review"].includes(r.status)).length, approved_awaiting_implementation: rows.filter((r) => r.status === "approved").length },
      };
    }
    case "leave_calendar": {
      if (!isDate(input.from_date) || !isDate(input.to_date)) return { error: "Χρειάζονται ημερομηνίες YYYY-MM-DD" };
      const rows = await all(() => { let q = db.from("hr_requests").select("id,ref,employee_name,employee_code,store,status,leave_type_label,start_date,end_date,days_requested,created_by").eq("category", "leave").neq("status", "draft"); if (input.store) q = q.eq("store", input.store); return q; });
      const ids = rows.map((r) => r.id);
      const dec = ids.length ? await all(() => db.from("hr_decisions").select("request_id,outcome,approved_start,approved_end,approved_days").in("request_id", ids).is("superseded_at", null)) : [];
      const D = Object.fromEntries(dec.map((d) => [d.request_id, d]));
      const overlaps = (a, b) => a && b && a <= input.to_date && b >= input.from_date;
      const approved = [], pending = [];
      for (const r of rows) {
        const d = D[r.id];
        if (["approved", "completed"].includes(r.status) && d?.outcome === "approve") {
          const a = d.approved_start || r.start_date, b = d.approved_end || r.end_date;
          if (overlaps(a, b)) approved.push({ employee: `${r.employee_name} (${r.employee_code})`, store: r.store, type: r.leave_type_label, from: dmy(a), to: dmy(b), days: d.approved_days ?? r.days_requested, ref: r.ref });
        } else if (input.include_pending !== false && ["submitted", "under_review", "needs_info", "awaiting_gm"].includes(r.status) && overlaps(r.start_date, r.end_date)) {
          pending.push({ employee: `${r.employee_name} (${r.employee_code})`, store: r.store, type: r.leave_type_label, from: dmy(r.start_date), to: dmy(r.end_date), days_requested: r.days_requested, status: REQ_STATUS_GR[r.status], ref: r.ref });
        }
      }
      return { period: `${dmy(input.from_date)} – ${dmy(input.to_date)}`, approved, pending, note: "Υπόλοιπο άδειας δεν τηρείται στο σύστημα." };
    }
    case "stats_report": {
      const kind = input.kind;
      if (!KINDS[kind]) return { error: "Άγνωστη ειδικότητα στατιστικών" };
      if (!isDate(input.from_date) || !isDate(input.to_date) || input.to_date < input.from_date) return { error: "Χρειάζεται διάστημα YYYY-MM-DD (από ≤ έως)" };
      const rows0 = await all(() => { let q = db.from("daily_stats").select("*").eq("kind", kind).gte("stat_date", input.from_date).lte("stat_date", input.to_date).order("stat_date"); if (input.store) q = q.eq("store", input.store); return q; });
      const names = Object.fromEntries((await all(() => db.from("employees").select("code,first,last"))).map((e) => [e.code, `${e.first} ${e.last}`]));
      const emp = input.employee ? matchesEmployee(input.employee) : null;
      const rows = rows0.filter((r) => !emp || emp(names[r.employee_code] || "", r.employee_code));
      const days = daysBetween(input.from_date, input.to_date).length;
      const fmt = (rs, extra = {}) => { const t = totals(rs, kind), m = metrics(t, kind); return { ...extra, entries: t.days, ...Object.fromEntries(KINDS[kind].fields.map((f) => [f, t[f]])), ...(kind !== "exclusive" ? { informed: t.informed, total_enrollments_dr_plus_cb: t.total_enr } : {}), rates: Object.fromEntries(KINDS[kind].metrics.map((x) => [x.label, pct(m[x.key])])), warnings: warnings(t, kind) }; };
      const group = (keyFn, label) => { const g = new Map(); for (const r of rows) { const k = keyFn(r); if (!g.has(k)) g.set(k, []); g.get(k).push(r); } return [...g].map(([k, rs]) => fmt(rs, label(k, rs))); };
      const by = input.group_by || "employee";
      return {
        specialty: KINDS[kind].label, period: `${dmy(input.from_date)} – ${dmy(input.to_date)} (${days} ημέρες, συμπεριλαμβάνονται και οι δύο)`,
        formulas: KINDS[kind].metrics.map((x) => `${x.label} = ${x.formula}`),
        overall: fmt(rows),
        groups: by === "none" ? undefined
          : by === "store" ? group((r) => r.store, (k) => ({ store: k }))
          : by === "day" ? group((r) => r.stat_date, (k) => ({ date: dmy(k) }))
          : group((r) => `${r.employee_code}|${r.store}`, (k, rs) => ({ employee: `${names[rs[0].employee_code] || rs[0].employee_code} (${rs[0].employee_code})`, store: rs[0].store, days_with_entry: `${rs.length}/${days}` })),
        rules: "Ποσοστά από αθροίσματα (όχι μέσος όρος). «—» = μηδενικός παρονομαστής. Οι προειδοποιήσεις είναι για έλεγχο, όχι λάθη. Δεν αθροίζονται διαφορετικές ειδικότητες. Δεν υπάρχουν στόχοι ή συνολική βαθμολογία.",
      };
    }
    case "missing_stats": {
      if (!isDate(input.date)) return { error: "Χρειάζεται ημερομηνία YYYY-MM-DD" };
      const [emps, specs, rows] = await Promise.all([
        all(() => { let q = db.from("employees").select("code,first,last,store,specialty,status").eq("status", "Ενεργός"); if (input.store) q = q.eq("store", input.store); return q; }),
        all(() => db.from("specialties").select("name,stat_kind")),
        all(() => { let q = db.from("daily_stats").select("employee_code,specialty").eq("stat_date", input.date); if (input.store) q = q.eq("store", input.store); return q; }),
      ]);
      const kind = Object.fromEntries(specs.map((s) => [s.name, s.stat_kind]));
      const have = new Set(rows.map((r) => `${r.employee_code}|${r.specialty}`));
      const with_stats = emps.filter((e) => kind[e.specialty]);
      const missing = with_stats.filter((e) => !have.has(`${e.code}|${e.specialty}`)).map((e) => ({ employee: `${e.first} ${e.last} (${e.code})`, store: e.store, specialty: e.specialty }));
      return { date: dmy(input.date), employees_with_stats: with_stats.length, entered: with_stats.length - missing.length, missing, without_specialty: emps.filter((e) => !e.specialty).map((e) => `${e.first} ${e.last} (${e.code})`) };
    }
    case "assessments_overview": {
      const { data: open, error } = await db.rpc("assessments_open");
      if (error) return { error: error.message };
      let list = (open || []).map((q) => ({ ...q, status: "active" }));
      if (["owner", "hr"].includes(me.role)) {
        const qs = await all(() => db.from("questionnaires").select("id,title,description,specialties,starts_at,ends_at,status"));
        list = qs.map((q) => ({ ...q, version: list.find((o) => o.id === q.id)?.version }));
      }
      if (input.title) list = list.filter((q) => norm(q.title).includes(norm(input.title)));
      const out = [];
      for (const q of list.slice(0, 20)) {
        let counts = null;
        if (q.status !== "draft") {
          const { data: t } = await db.rpc("assessment_targets", { p_qid: q.id });
          counts = {}; for (const x of t || []) counts[ATTEMPT_GR[x.state]] = (counts[ATTEMPT_GR[x.state]] || 0) + 1;
        }
        out.push({ title: q.title, status: { draft: "Πρόχειρο", active: "Ενεργό", closed: "Κλειστό" }[q.status], active_version: q.version ?? null, specialties: q.specialties, available: q.starts_at ? `${athens(q.starts_at)} → ${athens(q.ends_at)} (ώρα Ελλάδας)` : "δεν έχει οριστεί", employees_in_your_scope: counts });
      }
      return { count: out.length, questionnaires: out };
    }
    case "assessment_results": {
      const emp = input.employee ? matchesEmployee(input.employee) : null;
      if (!["owner", "hr"].includes(me.role)) {
        // Manager / εκπαιδευτής: μόνο κατάσταση, χωρίς βαθμούς
        const { data: open } = await db.rpc("assessments_open");
        const out = [];
        for (const q of (open || []).filter((q) => !input.title || norm(q.title).includes(norm(input.title)))) {
          const { data: t } = await db.rpc("assessment_targets", { p_qid: q.id });
          for (const x of t || []) {
            if ((emp && !emp(x.employee_name, x.employee_code)) || (input.store && x.store !== input.store) || (input.specialty && x.specialty !== input.specialty) || (input.state && x.state !== input.state)) continue;
            out.push({ questionnaire: q.title, employee: `${x.employee_name} (${x.employee_code})`, store: x.store, state: ATTEMPT_GR[x.state], submitted: athens(x.submitted_at) });
          }
        }
        return { note: "Βαθμούς και απαντήσεις βλέπουν μόνο η Γενική Διευθύντρια και το HR.", count: out.length, rows: out.slice(0, 300) };
      }
      const [qs, vers, atts] = await Promise.all([
        all(() => db.from("questionnaires").select("id,title,ends_at,status")),
        all(() => db.from("questionnaire_versions").select("id,version")),
        all(() => db.from("assessment_attempts").select("questionnaire_id,version_id,employee_code,employee_name,store,specialty,opened_by,started_at,submitted_at,status,score,max_score")),
      ]);
      const Q = Object.fromEntries(qs.map((q) => [q.id, q])), V = Object.fromEntries(vers.map((v) => [v.id, v.version]));
      const pickQ = qs.filter((q) => !input.title || norm(q.title).includes(norm(input.title)));
      const rows = [];
      for (const a of atts) {
        if (!pickQ.some((q) => q.id === a.questionnaire_id)) continue;
        const state = a.status === "in_progress" && Q[a.questionnaire_id]?.ends_at && new Date(Q[a.questionnaire_id].ends_at) < new Date() ? "expired" : a.status;
        rows.push({ q: a.questionnaire_id, code: a.employee_code, name: a.employee_name, store: a.store, specialty: a.specialty, state, version: V[a.version_id], opened_by: a.opened_by, submitted: athens(a.submitted_at), score: a.score, max: a.max_score });
      }
      // όσοι δεν ξεκίνησαν (για ενεργά/κλειστά ερωτηματολόγια)
      for (const q of pickQ.filter((q) => q.status !== "draft")) {
        const { data: t } = await db.rpc("assessment_targets", { p_qid: q.id });
        for (const x of (t || []).filter((x) => x.state === "not_started")) rows.push({ q: q.id, code: x.employee_code, name: x.employee_name, store: x.store, specialty: x.specialty, state: "not_started" });
      }
      const filtered = rows.filter((r) => (!emp || emp(r.name, r.code)) && (!input.store || r.store === input.store) && (!input.specialty || r.specialty === input.specialty) && (!input.state || r.state === input.state));
      // Μέσος όρος μόνο ανά ερωτηματολόγιο + έκδοση (συγκρίσιμοι κανόνες βαθμολόγησης)
      const avg = {};
      for (const r of filtered) if (r.state === "submitted" && r.max > 0 && r.score !== null) { const k = `${Q[r.q].title} · έκδοση ${r.version}`; (avg[k] ??= []).push((100 * r.score) / r.max); }
      return {
        count: filtered.length,
        rows: filtered.slice(0, 300).map((r) => ({ questionnaire: Q[r.q]?.title, version: r.version ?? null, employee: `${r.name} (${r.code})`, store_at_the_time: r.store, specialty: r.specialty, state: ATTEMPT_GR[r.state], opened_by: r.opened_by, submitted: r.submitted, result: r.max ? `${r.score ?? "—"} / ${r.max}${r.score !== null && r.score !== undefined ? ` (${pct((100 * r.score) / r.max)})` : ""}` : "χωρίς βαθμολόγηση" })),
        average_per_version: Object.fromEntries(Object.entries(avg).map(([k, v]) => [k, `${pct(v.reduce((s, x) => s + x, 0) / v.length)} (${v.length} βαθμολογημένες)`])),
        rules: "Οι βαθμοί συγκρίνονται μόνο μέσα στην ίδια έκδοση. Αυτοαξιολόγηση δεν έχει σωστό/λάθος. Δεν συνδυάζονται με στατιστικά πωλήσεων.",
      };
    }
  }
  return null;
}

export const hrToolNames = new Set(hrTools.map((t) => t.name));
export { athensToday };
