// Κοινά εργαλεία για τις Edge Functions
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("ANON_KEY") ?? "";

export function adminClient(): SupabaseClient {
  if (!SERVICE) throw new Error("Λείπει το service role key στις ρυθμίσεις του server.");
  return createClient(URL_, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** Client που τρέχει με τα δικαιώματα του συνδεδεμένου χρήστη (ισχύει το RLS). */
export function userClient(req: Request): SupabaseClient {
  const key = ANON || req.headers.get("apikey") || "";
  return createClient(URL_, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
}

export type Me = { email: string; name: string; role: "owner" | "hr" | "manager" | "trainer"; store: string | null };

/** Επαληθεύει το token και επιστρέφει τον χρήστη της εφαρμογής (ή null). */
export async function currentUser(req: Request): Promise<Me | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const admin = adminClient();
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user?.email) return null;
  const { data: row } = await admin
    .from("app_users")
    .select("email,name,role,store,active")
    .eq("email", data.user.email.toLowerCase())
    .maybeSingle();
  if (!row || !row.active) return null;
  return row as Me;
}
