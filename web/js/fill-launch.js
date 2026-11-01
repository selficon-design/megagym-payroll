// Άνοιγμα απομονωμένης φόρμας εργαζομένου στη συσκευή του εξουσιοδοτημένου χρήστη.
// Η συσκευή ΑΠΟΣΥΝΔΕΕΤΑΙ από τον λογαριασμό· η φόρμα έχει μόνο ένα κλειδί μίας χρήσης.
// Η επιστροφή στη διαχείριση απαιτεί ξανά email και κωδικό.
import { S } from "./core.js";
import { confirmBox, toast } from "./util.js";

export async function enterFill({ kind, label, start, returnTo }) {
  if (S.api.mode === "demo") return toast("Η φόρμα εργαζομένου λειτουργεί μόνο με σύνδεση στη βάση.", true);
  const ok = await confirmBox(
    "Παράδοση συσκευής στον εργαζόμενο",
    `Θα ανοίξει ΜΟΝΟ η φόρμα «${label}» και θα αποσυνδεθείτε από αυτή τη συσκευή, ώστε ο εργαζόμενος να μην έχει πρόσβαση σε άλλες καρτέλες ή δεδομένα. Για να επιστρέψετε θα χρειαστεί ο κωδικός σας.`,
    { ok: "Άνοιγμα φόρμας" }
  );
  if (!ok) return;
  const res = await start();
  sessionStorage.setItem("mg-fill", JSON.stringify({ token: res.token, sessionId: res.session_id, kind, label, openedBy: res.opened_by, returnTo }));
  history.replaceState(null, "", location.pathname + "#/fill");
  try { await S.api.signOutLocal(); }
  catch (e) { sessionStorage.removeItem("mg-fill"); await S.api.fillCancel(res.session_id).catch(() => {}); throw e; }
  location.reload();
}

/** Μετά την επιστροφή του χρήστη: κλείνει ό,τι έμεινε ανοιχτό και ενημερώνει. */
export async function afterFillReturn() {
  let st; try { st = JSON.parse(sessionStorage.getItem("mg-fill-return") || "null"); } catch {}
  sessionStorage.removeItem("mg-fill-return");
  if (!st?.sessionId) return;
  try {
    const s = await S.api.fillStatus(st.sessionId);
    if (s && !s.completed && !s.cancelled) {
      await S.api.fillCancel(st.sessionId);
      toast(st.kind === "assessment" ? "Η αξιολόγηση δεν υποβλήθηκε· οι προσωρινές απαντήσεις κρατήθηκαν και μπορεί να συνεχιστεί εντός του διαστήματος." : "Η φόρμα έκλεισε χωρίς ολοκλήρωση από τον εργαζόμενο.", true);
    } else if (s?.completed) {
      toast(st.kind === "assessment" ? "Ο εργαζόμενος υπέβαλε την αξιολόγηση." : "Ο εργαζόμενος ολοκλήρωσε τη φόρμα. Ελέγξτε και υποβάλετε το αίτημα.");
    }
  } catch {}
}
