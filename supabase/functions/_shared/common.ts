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
// Πρώτα τα κλειδιά που το αυτόματο deploy παίρνει φρέσκα από το project σε κάθε εκτέλεση (και ελέγχει),
// μετά όσα δίνει αυτόματα η πλατφόρμα.
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const ANON = Deno.env.get("ANON_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";

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

export type Identity = { me: Me | null; status: number; error?: string };

/**
 * Ποιος είναι ο χρήστης και τι ρόλο έχει — με ΤΟΝ ΙΔΙΟ έλεγχο που χρησιμοποιεί η εφαρμογή (whoami στη βάση).
 * Η βάση επαληθεύει την υπογραφή του token και διαβάζει τον ρόλο από τον πίνακα app_users (μόνο ενεργοί).
 * Κάθε αποτυχία επιστρέφεται με τη δική της αιτία, ώστε ένα τεχνικό πρόβλημα να μη φαίνεται σαν «δεν έχετε δικαίωμα».
 */
export async function identify(req: Request): Promise<Identity> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token || (ANON && token === ANON)) {
    return { me: null, status: 401, error: "Δεν υπάρχει ενεργή σύνδεση. Αποσυνδεθείτε και συνδεθείτε ξανά." };
  }
  const { data, error } = await userClient(req).rpc("whoami");
  if (error) {
    if (/jwt|token|expired|permission denied for function/i.test(error.message)) {
      return { me: null, status: 401, error: "Η σύνδεση έληξε ή δεν είναι έγκυρη. Αποσυνδεθείτε και συνδεθείτε ξανά." };
    }
    console.error("whoami", error);
    return { me: null, status: 500, error: "Δεν ήταν δυνατός ο έλεγχος δικαιωμάτων: " + error.message };
  }
  if (!data?.email) return { me: null, status: 401, error: "Η σύνδεση δεν είναι έγκυρη. Αποσυνδεθείτε και συνδεθείτε ξανά." };
  if (!data.role) return { me: null, status: 403, error: `Ο λογαριασμός ${data.email} δεν έχει ενεργό ρόλο στην εφαρμογή.` };
  return { me: { email: data.email, name: data.name, role: data.role, store: data.store ?? null }, status: 200 };
}

/** Ο χρήστης της εφαρμογής (ή null). */
export async function currentUser(req: Request): Promise<Me | null> {
  return (await identify(req)).me;
}
