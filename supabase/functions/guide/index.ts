// Οδηγός χρήσης: δίνεται μόνο σε όσους έχουν το δικαίωμα «guide.view» (πίνακας Ρόλοι & Δικαιώματα).
// Το κείμενο (content.ts) παράγεται από το docs/guide.md με το scripts/build-guide.mjs· ο έλεγχος
// tests/js/guide.test.mjs σταματά το deploy αν τα δύο διαφέρουν.
import { cors, identify, json } from "../_shared/common.ts";
import { GUIDE } from "./content.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const who = await identify(req);
  if (!who.me) return json({ error: who.error }, who.status);
  if (!who.me.perms.includes("guide.view")) return json({ error: "Δεν έχετε πρόσβαση στον Οδηγό χρήσης. Ζητήστε την από τη Γενική Διεύθυνση." }, 403);
  return json({ markdown: GUIDE });
});
