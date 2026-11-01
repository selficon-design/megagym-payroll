// Σύνδεση με τη βάση Supabase. Όλοι οι έλεγχοι δικαιωμάτων γίνονται στη βάση (RLS).
import { loadScript } from "./util.js";

function friendly(err) {
  const m = String(err?.message || err || "");
  if (/Invalid login credentials/i.test(m)) return "Λάθος email ή κωδικός.";
  if (/banned|User is banned/i.test(m)) return "Ο λογαριασμός είναι κλειδωμένος. Επικοινωνήστε με τη Γενική Διευθύντρια.";
  if (/row-level security|permission denied/i.test(m)) return "Δεν έχετε δικαίωμα για αυτή την ενέργεια.";
  if (/duplicate key|already exists|unique/i.test(m)) return "Υπάρχει ήδη εγγραφή με αυτά τα στοιχεία.";
  if (/violates foreign key/i.test(m)) return "Η εγγραφή χρησιμοποιείται αλλού και δεν μπορεί να αλλάξει έτσι.";
  if (/Failed to fetch|NetworkError|network/i.test(m)) return "Δεν υπάρχει σύνδεση στο internet. Δοκιμάστε ξανά.";
  if (/JWT|expired/i.test(m)) return "Η σύνδεση έληξε. Συνδεθείτε ξανά.";
  return m || "Προέκυψε σφάλμα.";
}
const check = ({ data, error }) => { if (error) throw new Error(friendly(error)); return data; };

export async function createSupabaseApi(cfg) {
  await loadScript("vendor/supabase.js");
  const sb = window.supabase.createClient(cfg.url, cfg.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: "mega-payroll-auth" },
  });

  // Φέρνει όλες τις γραμμές (η βάση δίνει έως 1000 ανά αίτημα)
  async function all(build) {
    const out = [];
    for (let from = 0; ; from += 1000) {
      const data = check(await build().range(from, from + 999));
      out.push(...data);
      if (data.length < 1000) return out;
    }
  }
  async function fn(name, body) {
    const { data, error } = await sb.functions.invoke(name, { body });
    if (error) {
      let msg = error.message;
      try { const j = await error.context.json(); msg = j.error || msg; } catch {}
      throw new Error(friendly(msg));
    }
    return data;
  }

  const rpc = async (name, args) => check(await sb.rpc(name, args));
  const DECL_COLS = "id,employee_code,employee_name,store,company,month,end_date,period,amount,status,signer,signed_at,signed_by,prepared_by,prepared_at,voided_by,voided_at,void_reason";

  return {
    mode: "live",
    onAuthChange(cb) { sb.auth.onAuthStateChange((ev) => { if (ev === "SIGNED_OUT") cb(); }); },
    async session() {
      const { data } = await sb.auth.getSession();
      if (!data.session) return null;
      return check(await sb.rpc("whoami"));
    },
    async signIn(email, password) {
      const { error } = await sb.auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
      if (error) throw new Error(friendly(error));
    },
    async signOut() { await sb.auth.signOut(); },
    /** Αποσύνδεση ΜΟΝΟ αυτής της συσκευής (πριν από την απομονωμένη φόρμα εργαζομένου). */
    async signOutLocal() {
      await sb.auth.signOut({ scope: "local" }).catch(() => {});
      try { localStorage.removeItem("mega-payroll-auth"); } catch {}
      const { data } = await sb.auth.getSession();
      if (data.session) throw new Error("Δεν ήταν δυνατή η αποσύνδεση από τη συσκευή.");
    },
    async verifyPassword(password) {
      const { data } = await sb.auth.getUser();
      const { error } = await sb.auth.signInWithPassword({ email: data.user.email, password });
      if (error) throw new Error("Λάθος κωδικός.");
    },
    async changePassword(password) { const { error } = await sb.auth.updateUser({ password }); if (error) throw new Error(friendly(error)); },

    async lists() {
      const [stores, companies, specialties] = await Promise.all([
        sb.from("stores").select("*").order("sort").order("name").then(check),
        sb.from("companies").select("*").order("sort").order("name").then(check),
        sb.from("specialties").select("*").order("sort").order("name").then(check),
      ]);
      return { stores, companies, specialties };
    },
    async saveStore(s, isNew) { check(isNew ? await sb.from("stores").insert(s) : await sb.from("stores").update(s).eq("name", s.name)); },
    async saveCompany(c, isNew) { check(isNew ? await sb.from("companies").insert(c) : await sb.from("companies").update(c).eq("name", c.name)); },

    employees: () => all(() => sb.from("employees").select("*").order("last").order("first")),
    async saveEmployee(e, isNew) {
      if (isNew) check(await sb.from("employees").insert(e));
      else { const { code, ...rest } = e; check(await sb.from("employees").update(rest).eq("code", code)); }
    },
    async importEmployees(rows) {
      for (let i = 0; i < rows.length; i += 400) check(await sb.from("employees").upsert(rows.slice(i, i + 400), { onConflict: "code" }));
      return rows.length;
    },

    monthStatus: (month) => all(() => sb.rpc("month_status", { p_month: month })),
    declarations({ month, status, store } = {}) {
      return all(() => {
        let q = sb.from("declarations").select(DECL_COLS).order("month", { ascending: false }).order("signed_at", { ascending: false, nullsFirst: false });
        if (month) q = q.eq("month", month);
        if (status) q = q.eq("status", status);
        if (store) q = q.eq("store", store);
        return q;
      });
    },
    async declaration(id) { return check(await sb.from("declarations").select("*").eq("id", id).single()); },
    async declarationsFull(ids) {
      const out = [];
      for (let i = 0; i < ids.length; i += 50) out.push(...check(await sb.from("declarations").select("*").in("id", ids.slice(i, i + 50))));
      return out;
    },
    async prepare(month, rows) { return check(await sb.rpc("prepare_declarations", { p_month: month, p_rows: rows })); },
    async sign(id, signer, signature) {
      return check(await sb.rpc("sign_declaration", { p_id: id, p_signer: signer, p_signature: signature, p_device: navigator.userAgent.slice(0, 300) }));
    },
    async voidDeclaration(id, reason) { return check(await sb.rpc("void_declaration", { p_id: id, p_reason: reason })); },
    async discardPending(id) { return check(await sb.rpc("discard_pending", { p_id: id })); },

    users: () => all(() => sb.from("app_users").select("*").order("role").order("name")),
    async userStatuses() { try { return (await fn("admin-users", { action: "statuses" })).users || {}; } catch { return null; } },
    async saveUser(u) { check(await sb.from("app_users").upsert(u, { onConflict: "email" })); },
    async setPassword(email, password) { return fn("admin-users", { action: "set_password", email, password }); },
    async setActive(email, active) {
      check(await sb.from("app_users").update({ active }).eq("email", email));
      await fn("admin-users", { action: active ? "unlock" : "lock", email });
    },
    async deleteUser(email) {
      check(await sb.from("app_users").delete().eq("email", email));
      await fn("admin-users", { action: "delete", email });
    },

    async audit({ limit = 200, entity, before } = {}) {
      let q = sb.from("audit_log").select("*").order("at", { ascending: false }).limit(limit);
      if (entity) q = q.eq("entity", entity);
      if (before) q = q.lt("at", before);
      return check(await q);
    },

    async ask(messages) { const r = await fn("ask", { messages }); return r.answer; },
    ...hrApi(sb, all, rpc),
  };
}

// ═══════════ Καρτέλα εργαζομένου, αιτήματα, πρότυπα, στατιστικά, αξιολογήσεις ═══════════
function hrApi(sb, all, rpc) {
  const REQ_COLS = "id,ref,process,category,employee_code,employee_name,store,company,specialty,status,entry_mode,stated_by,written_by,submitted_by,submitted_at,created_by,created_at,updated_at,assignee,leave_type,leave_type_label,start_date,end_date,days_requested,incident_date,notified_at,completed_at,version";
  return {
    // Ειδικότητες, εκπαιδευτές, ιστορικό θέσεων
    async saveSpecialty(x, isNew) { check(isNew ? await sb.from("specialties").insert(x) : await sb.from("specialties").update(x).eq("name", x.name)); },
    trainerScopes: () => all(() => sb.from("trainer_scopes").select("*").order("email")),
    async addTrainerScope(x) { check(await sb.from("trainer_scopes").insert(x)); },
    async removeTrainerScope(id) { check(await sb.from("trainer_scopes").delete().eq("id", id)); },
    trainerEmployees: () => rpc("trainer_employees"),
    async employee(code) { return check(await sb.from("employees").select("*").eq("code", code).maybeSingle()); },
    assignments: (code) => all(() => sb.from("employee_assignments").select("*").eq("employee_code", code).order("valid_from", { ascending: false })),
    handlers: () => rpc("hr_handlers"),

    // Πρότυπα κειμένων
    async templates() {
      const [keys, versions] = await Promise.all([
        all(() => sb.from("text_templates").select("*").order("sort")),
        all(() => sb.from("text_template_versions").select("*").order("version", { ascending: false })),
      ]);
      return keys.map((k) => { const v = versions.filter((x) => x.key === k.key); return { ...k, current: v[0], history: v }; });
    },
    templateSave: (key, body) => rpc("template_save", { p_key: key, p_body: body }),
    leaveTypes: () => all(() => sb.from("leave_types").select("*").order("sort")),
    async saveLeaveType(x, isNew) { check(isNew ? await sb.from("leave_types").insert(x) : await sb.from("leave_types").update(x).eq("code", x.code)); },
    rejectReasons: () => all(() => sb.from("reject_reasons").select("*").order("sort")),
    async saveRejectReason(x, isNew) { check(isNew ? await sb.from("reject_reasons").insert(x) : await sb.from("reject_reasons").update(x).eq("code", x.code)); },

    // Αιτήματα
    requests({ employee } = {}) {
      return all(() => { let q = sb.from("hr_requests").select(REQ_COLS).order("created_at", { ascending: false }); if (employee) q = q.eq("employee_code", employee); return q; });
    },
    async request(id) {
      const [r, decisions, events, attachments, internal] = await Promise.all([
        sb.from("hr_requests").select("*").eq("id", id).maybeSingle().then(check),
        sb.from("hr_decisions").select("*").eq("request_id", id).order("decided_at").then(check),
        sb.from("hr_request_events").select("*").eq("request_id", id).order("at").then(check),
        sb.from("hr_attachments").select("id,filename,mime,size,uploaded_by,uploaded_at").eq("request_id", id).order("uploaded_at").then(check),
        sb.from("hr_request_internal").select("*").eq("request_id", id).maybeSingle().then(check),
      ]);
      if (!r) throw new Error("Το αίτημα δεν βρέθηκε ή δεν έχετε πρόσβαση.");
      return { ...r, decisions, events, attachments, internal };
    },
    decisionsFor: (ids) => ids.length ? all(() => sb.from("hr_decisions").select("*").in("request_id", ids).is("superseded_at", null)) : [],
    async attachment(id) { return check(await sb.from("hr_attachments").select("*").eq("id", id).single()); },
    reqCreate: (p) => rpc("req_create", { p }),
    reqUpdateDraft: (id, p, v) => rpc("req_update_draft", { p_id: id, p, p_version: v }),
    reqSubmit: (id, v) => rpc("req_submit", { p_id: id, p_version: v }),
    reqDelete: (id, v) => rpc("req_delete_draft", { p_id: id, p_version: v }),
    reqAssign: (id, email, v) => rpc("req_assign", { p_id: id, p_email: email, p_version: v }),
    reqForward: (id, note, v) => rpc("req_forward_gm", { p_id: id, p_note: note, p_version: v }),
    reqWarningDraft: (id, text, send, v) => rpc("req_warning_draft", { p_id: id, p_text: text, p_send: send, p_version: v }),
    reqDecide: (id, outcome, p, v) => rpc("req_decide", { p_id: id, p_outcome: outcome, p, p_version: v }),
    reqProvideInfo: (id, note, v) => rpc("req_provide_info", { p_id: id, p_note: note, p_version: v }),
    reqNotified: (id, at, note, v) => rpc("req_mark_notified", { p_id: id, p_at: at, p_note: note, p_version: v }),
    reqComplete: (id, note, v) => rpc("req_complete", { p_id: id, p_note: note, p_version: v }),
    reqAttach: (id, f) => rpc("req_attach", { p_id: id, p_filename: f.name, p_mime: f.mime, p_data: f.data }),

    // Απομονωμένη συμπλήρωση
    fillStartRequest: (id) => rpc("fill_start_request", { p_request_id: id }),
    fillStartAssessment: (qid, code) => rpc("fill_start_assessment", { p_qid: qid, p_code: code }),
    fillCancel: (sid) => rpc("fill_cancel", { p_session: sid }),
    fillStatus: (sid) => rpc("fill_status", { p_session: sid }),

    // Στατιστικά
    stats({ from, to, store, employee } = {}) {
      return all(() => {
        let q = sb.from("daily_stats").select("*").order("stat_date").order("store").order("employee_code");
        if (from) q = q.gte("stat_date", from); if (to) q = q.lte("stat_date", to);
        if (store) q = q.eq("store", store); if (employee) q = q.eq("employee_code", employee);
        return q;
      });
    },
    statsSave: (date, rows) => rpc("stats_save", { p_date: date, p_rows: rows }),
    statsHistory: (id) => all(() => sb.from("daily_stats_history").select("*").eq("stats_id", id).order("changed_at", { ascending: false })),

    // Αξιολογήσεις
    questionnaires: () => all(() => sb.from("questionnaires").select("*").order("created_at", { ascending: false })),
    async questionnaire(id) {
      const [q, versions, log] = await Promise.all([
        sb.from("questionnaires").select("*").eq("id", id).maybeSingle().then(check),
        sb.from("questionnaire_versions").select("*").eq("questionnaire_id", id).order("version", { ascending: false }).then(check),
        sb.from("questionnaire_window_log").select("*").eq("questionnaire_id", id).order("at", { ascending: false }).then(check),
      ]);
      if (!q) throw new Error("Το ερωτηματολόγιο δεν βρέθηκε.");
      return { ...q, versions, log };
    },
    questions: (versionId) => all(() => sb.from("assessment_questions").select("*").eq("version_id", versionId).order("sort").order("row_no")),
    versionsAll: () => all(() => sb.from("questionnaire_versions").select("id,questionnaire_id,version,status")),
    qCreate: (title, description) => rpc("q_create", { p_title: title, p_description: description }),
    qUpdateMeta: (id, m) => rpc("q_update_meta", { p_id: id, p_title: m.title, p_description: m.description, p_specialties: m.specialties, p_participants: m.participants }),
    qParse: (rows) => rpc("q_parse_rows", { p_rows: rows }),
    qSaveQuestions: (id, rows, filename) => rpc("q_save_questions", { p_id: id, p_rows: rows, p_filename: filename }),
    qSetMultiRule: (id, rule) => rpc("q_set_multi_rule", { p_id: id, p_rule: rule }),
    qSetWindow: (id, s, e, note) => rpc("q_set_window", { p_id: id, p_starts: s, p_ends: e, p_note: note }),
    qCheck: (id) => rpc("q_check", { p_id: id }),
    qPublish: (id) => rpc("q_publish", { p_id: id }),
    qClose: (id) => rpc("q_close", { p_id: id }),
    attempts({ questionnaire, employee } = {}) {
      return all(() => {
        let q = sb.from("assessment_attempts").select("id,questionnaire_id,version_id,employee_code,employee_name,store,specialty,company,opened_by,opened_role,started_at,last_saved_at,submitted_at,status,score,max_score").order("started_at", { ascending: false });
        if (questionnaire) q = q.eq("questionnaire_id", questionnaire); if (employee) q = q.eq("employee_code", employee);
        return q;
      });
    },
    attemptAnswers: (id) => all(() => sb.from("assessment_answers").select("*").eq("attempt_id", id)),
    assessmentGrade: (attempt, question, points) => rpc("assessment_grade", { p_attempt: attempt, p_question: question, p_points: points }),
    assessmentsOpen: () => rpc("assessments_open"),
    assessmentTargets: (qid) => rpc("assessment_targets", { p_qid: qid }),
    employeeAssessments: (code) => rpc("employee_assessments", { p_code: code }),
  };
}

/** Σύνδεση για την απομονωμένη οθόνη εργαζομένου: ΧΩΡΙΣ λογαριασμό, μόνο με το κλειδί μίας χρήσης. */
export async function createFillApi(cfg) {
  await loadScript("vendor/supabase.js");
  const sb = window.supabase.createClient(cfg.url, cfg.anonKey, { auth: { persistSession: false, autoRefreshToken: false, storageKey: "mega-fill-none" } });
  const rpc = async (name, args) => check(await sb.rpc(name, args));
  return {
    mode: "live",
    get: (t) => rpc("fill_get", { p_token: t }),
    saveRequest: (t, p) => rpc("fill_save_request", { p_token: t, p }),
    attach: (t, f) => rpc("fill_attach", { p_token: t, p_filename: f.name, p_mime: f.mime, p_data: f.data }),
    finishRequest: (t) => rpc("fill_finish_request", { p_token: t }),
    saveAnswers: (t, a) => rpc("fill_save_answers", { p_token: t, p_answers: a }),
    submitAssessment: (t, a) => rpc("fill_submit_assessment", { p_token: t, p_answers: a }),
    // Επιστροφή του εξουσιοδοτημένου χρήστη: πλήρης είσοδος με κωδικό
    async signIn(email, password) {
      const main = window.supabase.createClient(cfg.url, cfg.anonKey, { auth: { persistSession: true, autoRefreshToken: true, storageKey: "mega-payroll-auth" } });
      const { error } = await main.auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
      if (error) throw new Error(friendly(error));
      const me = check(await main.rpc("whoami"));
      if (!me?.role) { await main.auth.signOut({ scope: "local" }); throw new Error("Ο λογαριασμός δεν έχει πρόσβαση."); }
      return me;
    },
  };
}
