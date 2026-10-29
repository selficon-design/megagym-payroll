// Σύνδεση με τη βάση Supabase. Όλοι οι έλεγχοι δικαιωμάτων γίνονται στη βάση (RLS).
import { loadScript } from "./util.js";

function friendly(err) {
  const m = String(err?.message || err || "");
  if (/Invalid login credentials/i.test(m)) return "Λάθος email ή κωδικός.";
  if (/banned|User is banned/i.test(m)) return "Ο λογαριασμός είναι κλειδωμένος. Επικοινωνήστε με την ιδιοκτήτρια.";
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
    async verifyPassword(password) {
      const { data } = await sb.auth.getUser();
      const { error } = await sb.auth.signInWithPassword({ email: data.user.email, password });
      if (error) throw new Error("Λάθος κωδικός.");
    },
    async changePassword(password) { const { error } = await sb.auth.updateUser({ password }); if (error) throw new Error(friendly(error)); },

    async lists() {
      const [stores, companies] = await Promise.all([
        sb.from("stores").select("*").order("sort").order("name").then(check),
        sb.from("companies").select("*").order("sort").order("name").then(check),
      ]);
      return { stores, companies };
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
  };
}
