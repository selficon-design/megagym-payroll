// Διαχείριση λογαριασμών σύνδεσης — μόνο για την ιδιοκτήτρια.
// Ο ρόλος/κατάστημα αποθηκεύεται από την εφαρμογή στον πίνακα app_users (με καταγραφή στο ιστορικό).
// Εδώ γίνονται μόνο όσα χρειάζονται το "κλειδί διαχειριστή": δημιουργία λογαριασμού, κωδικός, κλείδωμα, διαγραφή.
import { adminClient, cors, currentUser, json } from "../_shared/common.ts";

async function findAuthUser(email: string) {
  const admin = adminClient();
  for (let page = 1; page < 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((u) => (u.email ?? "").toLowerCase() === email);
    if (hit) return hit;
    if (data.users.length < 200) return null;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Μη έγκυρο αίτημα." }, 405);

  try {
    const me = await currentUser(req);
    if (!me || me.role !== "owner") return json({ error: "Μόνο η ιδιοκτήτρια διαχειρίζεται λογαριασμούς." }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "statuses") {
      // Κατάσταση λογαριασμού για όλους (για τη λίστα χρηστών)
      const admin0 = adminClient();
      const out: Record<string, unknown> = {};
      for (let page = 1; page < 50; page++) {
        const { data, error } = await admin0.auth.admin.listUsers({ page, perPage: 200 });
        if (error) throw error;
        for (const u of data.users) {
          out[(u.email ?? "").toLowerCase()] = {
            hasLogin: true,
            locked: !!u.banned_until && new Date(u.banned_until) > new Date(),
            lastSignIn: u.last_sign_in_at ?? null,
          };
        }
        if (data.users.length < 200) break;
      }
      return json({ ok: true, users: out });
    }

    const email = String(body.email ?? "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Μη έγκυρο email." }, 400);

    const admin = adminClient();
    const { data: appUser } = await admin.from("app_users").select("email,active").eq("email", email).maybeSingle();
    if (!appUser && action !== "delete") {
      return json({ error: "Αποθηκεύστε πρώτα τον χρήστη στη λίστα χρηστών." }, 400);
    }
    const existing = await findAuthUser(email);

    if (action === "set_password") {
      const password = String(body.password ?? "");
      if (password.length < 8) return json({ error: "Ο κωδικός χρειάζεται τουλάχιστον 8 χαρακτήρες." }, 400);
      if (existing) {
        const { error } = await admin.auth.admin.updateUserById(existing.id, { password, ban_duration: "none" });
        if (error) throw error;
        return json({ ok: true, created: false });
      }
      const { error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      if (error) throw error;
      return json({ ok: true, created: true });
    }

    if (action === "lock" || action === "unlock") {
      if (email === me.email && action === "lock") return json({ error: "Δεν μπορείτε να κλειδώσετε τον εαυτό σας." }, 400);
      if (existing) {
        const { error } = await admin.auth.admin.updateUserById(existing.id, {
          ban_duration: action === "lock" ? "876000h" : "none",
        });
        if (error) throw error;
      }
      return json({ ok: true });
    }

    if (action === "delete") {
      if (email === me.email) return json({ error: "Δεν μπορείτε να διαγράψετε τον εαυτό σας." }, 400);
      if (existing) {
        const { error } = await admin.auth.admin.deleteUser(existing.id);
        if (error) throw error;
      }
      return json({ ok: true });
    }

    if (action === "status") {
      return json({
        ok: true,
        hasLogin: !!existing,
        locked: !!existing?.banned_until && new Date(existing.banned_until) > new Date(),
        lastSignIn: existing?.last_sign_in_at ?? null,
      });
    }

    return json({ error: "Άγνωστη ενέργεια." }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "Δεν ολοκληρώθηκε: " + ((e as Error).message ?? "σφάλμα") }, 500);
  }
});
