// Βοηθός AI: απαντά σε ερωτήσεις για εργαζόμενους και δηλώσεις.
// Κάθε αναζήτηση τρέχει με τα δικαιώματα του χρήστη που ρωτά (RLS),
// άρα ένας manager παίρνει απαντήσεις μόνο για το κατάστημά του.
// Οι εικόνες υπογραφών δεν στέλνονται ποτέ στο μοντέλο.
import { cors, currentUser, json, userClient } from "../_shared/common.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = Deno.env.get("AI_MODEL") || "claude-haiku-5-5";

const STATUS_GR: Record<string, string> = {
  signed: "Υπογεγραμμένη", pending: "Προς υπογραφή", missing: "Χωρίς δήλωση", voided: "Ακυρωμένη",
};

const tools = [
  {
    name: "month_overview",
    description: "Σύνοψη ενός μήνα: ανά κατάστημα πόσοι ενεργοί εργαζόμενοι έχουν υπογράψει, πόσοι περιμένουν υπογραφή, πόσοι δεν έχουν δήλωση, και σύνολα ποσών.",
    input_schema: { type: "object", properties: { month: { type: "string", description: "YYYY-MM" } }, required: ["month"] },
  },
  {
    name: "list_by_status",
    description: "Λίστα εργαζομένων για έναν μήνα με την κατάσταση της δήλωσής τους. Φίλτρα: status (signed|pending|missing), store, company.",
    input_schema: {
      type: "object",
      properties: {
        month: { type: "string", description: "YYYY-MM" },
        status: { type: "string", enum: ["signed", "pending", "missing"] },
        store: { type: "string" },
        company: { type: "string" },
      },
      required: ["month"],
    },
  },
  {
    name: "find_employee",
    description: "Αναζήτηση εργαζομένου με όνομα, επώνυμο ή κωδικό. Επιστρέφει στοιχεία και ιστορικό δηλώσεων (μήνας, κατάσταση, ποσό, ημερομηνία υπογραφής).",
    input_schema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] },
  },
  {
    name: "totals",
    description: "Σύνολα ποσών και πλήθος δηλώσεων σε εύρος μηνών, ομαδοποιημένα ανά μήνα, κατάστημα ή εταιρεία.",
    input_schema: {
      type: "object",
      properties: {
        from_month: { type: "string", description: "YYYY-MM" },
        to_month: { type: "string", description: "YYYY-MM" },
        group_by: { type: "string", enum: ["month", "store", "company"] },
        only_signed: { type: "boolean" },
        store: { type: "string" },
        company: { type: "string" },
      },
      required: ["from_month", "to_month", "group_by"],
    },
  },
  {
    name: "employees_list",
    description: "Λίστα εργαζομένων (μητρώο) με φίλτρα κατάστημα, εταιρεία, κατάσταση (Ενεργός|Ανενεργός).",
    input_schema: {
      type: "object",
      properties: { store: { type: "string" }, company: { type: "string" }, status: { type: "string" } },
    },
  },
  {
    name: "recent_activity",
    description: "Πρόσφατες ενέργειες χρηστών (ποιος υπέγραψε/πρόσθεσε/άλλαξε τι και πότε). Διαθέσιμο μόνο για ιδιοκτήτρια και HR.",
    input_schema: { type: "object", properties: { limit: { type: "number" }, entity: { type: "string", enum: ["employees", "declarations", "app_users"] } } },
  },
];

const money = (n: number) => n.toLocaleString("el-GR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + "€";

async function runTool(db: SupabaseClient, name: string, input: Record<string, any>): Promise<unknown> {
  const month = /^\d{4}-\d{2}$/.test(input.month ?? "") ? input.month : null;
  switch (name) {
    case "month_overview": {
      if (!month) return { error: "Χρειάζεται μήνας YYYY-MM" };
      const { data, error } = await db.rpc("month_status", { p_month: month });
      if (error) return { error: error.message };
      const by: Record<string, any> = {};
      for (const r of data ?? []) {
        const s = (by[r.store] ??= { store: r.store, employees: 0, signed: 0, pending: 0, missing: 0, signed_total: 0, pending_total: 0 });
        s.employees++;
        s[r.status]++;
        if (r.status === "signed") s.signed_total += Number(r.amount);
        if (r.status === "pending") s.pending_total += Number(r.amount);
      }
      const stores = Object.values(by).map((s: any) => ({ ...s, signed_total: money(s.signed_total), pending_total: money(s.pending_total) }));
      return { month, stores };
    }
    case "list_by_status": {
      if (!month) return { error: "Χρειάζεται μήνας YYYY-MM" };
      const { data, error } = await db.rpc("month_status", { p_month: month });
      if (error) return { error: error.message };
      const rows = (data ?? [])
        .filter((r: any) => !input.status || r.status === input.status)
        .filter((r: any) => !input.store || r.store === input.store)
        .filter((r: any) => !input.company || r.company === input.company)
        .map((r: any) => ({
          code: r.code, name: `${r.first} ${r.last}`, store: r.store, company: r.company,
          status: STATUS_GR[r.status], amount: r.amount != null ? money(Number(r.amount)) : null,
          signed_at: r.signed_at,
        }));
      return { month, count: rows.length, rows: rows.slice(0, 300), truncated: rows.length > 300 };
    }
    case "find_employee": {
      const q = String(input.query ?? "").trim().replace(/[%,()]/g, " ");
      if (q.length < 2) return { error: "Πολύ σύντομη αναζήτηση" };
      const parts = q.split(/\s+/).filter(Boolean);
      let req = db.from("employees").select("code,first,last,store,company,status").limit(20);
      for (const p of parts) req = req.or(`first.ilike.%${p}%,last.ilike.%${p}%,code.ilike.%${p}%`);
      const { data: emps, error } = await req;
      if (error) return { error: error.message };
      const codes = (emps ?? []).map((e: any) => e.code);
      const { data: decls } = codes.length
        ? await db.from("declarations").select("employee_code,month,status,amount,signed_at,signer,period")
            .in("employee_code", codes).order("month", { ascending: false }).limit(200)
        : { data: [] as any[] };
      return (emps ?? []).map((e: any) => ({
        ...e,
        declarations: (decls ?? []).filter((d: any) => d.employee_code === e.code).slice(0, 24)
          .map((d: any) => ({ month: d.month, status: STATUS_GR[d.status], amount: money(Number(d.amount)), signed_at: d.signed_at, period: d.period })),
      }));
    }
    case "totals": {
      let req = db.from("declarations").select("month,store,company,status,amount")
        .gte("month", input.from_month).lte("month", input.to_month).neq("status", "voided").limit(20000);
      if (input.only_signed) req = req.eq("status", "signed");
      if (input.store) req = req.eq("store", input.store);
      if (input.company) req = req.eq("company", input.company);
      const { data, error } = await req;
      if (error) return { error: error.message };
      const key = input.group_by as "month" | "store" | "company";
      const g: Record<string, any> = {};
      for (const d of data ?? []) {
        const k = d[key];
        const s = (g[k] ??= { [key]: k, declarations: 0, signed: 0, pending: 0, total: 0, signed_total: 0 });
        s.declarations++; s[d.status]++;
        s.total += Number(d.amount);
        if (d.status === "signed") s.signed_total += Number(d.amount);
      }
      return Object.values(g).sort((a: any, b: any) => String(a[key]).localeCompare(String(b[key]), "el"))
        .map((s: any) => ({ ...s, total: money(s.total), signed_total: money(s.signed_total) }));
    }
    case "employees_list": {
      let req = db.from("employees").select("code,first,last,store,company,status").order("last").limit(1000);
      if (input.store) req = req.eq("store", input.store);
      if (input.company) req = req.eq("company", input.company);
      if (input.status) req = req.eq("status", input.status);
      const { data, error } = await req;
      if (error) return { error: error.message };
      return { count: data?.length ?? 0, rows: data };
    }
    case "recent_activity": {
      let req = db.from("audit_log").select("at,actor,action,entity,entity_id,details")
        .order("at", { ascending: false }).limit(Math.min(Number(input.limit) || 30, 100));
      if (input.entity) req = req.eq("entity", input.entity);
      const { data, error } = await req;
      if (error) return { error: error.message };
      if (!data?.length) return { note: "Δεν υπάρχουν εγγραφές ή ο χρήστης δεν έχει πρόσβαση στο ιστορικό." };
      return data;
    }
  }
  return { error: "Άγνωστο εργαλείο" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!API_KEY) return json({ error: "Ο Βοηθός AI δεν έχει ενεργοποιηθεί (λείπει το ANTHROPIC_API_KEY)." }, 503);
    const me = await currentUser(req);
    if (!me) return json({ error: "Δεν επιτρέπεται η πρόσβαση." }, 403);

    const body = await req.json().catch(() => ({}));
    const history = Array.isArray(body.messages) ? body.messages.slice(-12) : [];
    const messages: any[] = history
      .filter((m: any) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim())
      .map((m: any) => ({ role: m.role, content: m.content.slice(0, 4000) }));
    if (!messages.length || messages[messages.length - 1].role !== "user") return json({ error: "Γράψτε μια ερώτηση." }, 400);

    const db = userClient(req);
    const [{ data: stores }, { data: companies }] = await Promise.all([
      db.from("stores").select("name").order("sort"),
      db.from("companies").select("name").order("sort"),
    ]);
    const now = new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Athens" }));
    const thisMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const roleGr = me.role === "owner" ? "Ιδιοκτήτρια (βλέπει τα πάντα)" : me.role === "hr" ? "HR (βλέπει όλα τα καταστήματα)" : `Manager καταστήματος ${me.store} (βλέπει μόνο αυτό)`;

    const system = `Είσαι ο Βοηθός της εφαρμογής «Δηλώσεις μισθοδοσίας» της MEGA GYM.
Απαντάς ΠΑΝΤΑ στα ελληνικά, σύντομα και καθαρά, με βάση ΜΟΝΟ όσα επιστρέφουν τα εργαλεία. Ποτέ μην επινοείς ονόματα, ποσά ή αριθμούς.
Σήμερα: ${now.toLocaleDateString("el-GR")} · τρέχων μήνας: ${thisMonth}. Όταν ο χρήστης λέει «αυτόν τον μήνα», «τον Οκτώβριο» κ.λπ., μετάτρεψέ το σε YYYY-MM (χωρίς έτος = το πιο πρόσφατο έτος που δεν είναι στο μέλλον).
Χρήστης: ${me.name} — ${roleGr}. Αν ζητήσει κάτι εκτός δικαιωμάτων του, εξήγησε ευγενικά ότι δεν έχει πρόσβαση.
Καταστήματα: ${(stores ?? []).map((s: any) => s.name).join(", ")}.
Εταιρείες: ${(companies ?? []).map((c: any) => c.name).join(", ")}.
Καταστάσεις δήλωσης: Υπογεγραμμένη, Προς υπογραφή (έχει ετοιμαστεί, περιμένει τον εργαζόμενο), Χωρίς δήλωση (δεν έχει ετοιμαστεί).
Μορφή απάντησης: ξεκίνα με την ουσία (π.χ. «Λείπουν 3 υπογραφές:»), μετά λίστα με παύλες αν χρειάζεται. Χρησιμοποίησε **έντονα** μόνο για σημαντικούς αριθμούς. Για μεγάλες λίστες δείξε έως 30 και ανέφερε πόσες ακόμη υπάρχουν.
Δεν μπορείς να αλλάξεις δεδομένα· για ενέργειες (υπογραφή, προετοιμασία, προσθήκη εργαζομένου) πες στον χρήστη από ποια ενότητα της εφαρμογής γίνονται.`;

    for (let step = 0; step < 8; step++) {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: MODEL, max_tokens: 1500, system, tools, messages }),
      });
      const out = await r.json();
      if (!r.ok) {
        console.error(out);
        return json({ error: "Ο Βοηθός δεν απάντησε: " + (out?.error?.message ?? r.status) }, 502);
      }
      messages.push({ role: "assistant", content: out.content });
      if (out.stop_reason !== "tool_use") {
        const text = (out.content ?? []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("\n").trim();
        return json({ answer: text || "Δεν βρήκα απάντηση." });
      }
      const results = [];
      for (const c of out.content) {
        if (c.type !== "tool_use") continue;
        let result: unknown;
        try { result = await runTool(db, c.name, c.input ?? {}); } catch (e) { result = { error: String(e) }; }
        results.push({ type: "tool_result", tool_use_id: c.id, content: JSON.stringify(result).slice(0, 60000) });
      }
      messages.push({ role: "user", content: results });
    }
    return json({ answer: "Η ερώτηση χρειάστηκε πολλά βήματα. Δοκιμάστε να τη διατυπώσετε πιο συγκεκριμένα." });
  } catch (e) {
    console.error(e);
    return json({ error: "Σφάλμα Βοηθού: " + ((e as Error).message ?? "") }, 500);
  }
});
