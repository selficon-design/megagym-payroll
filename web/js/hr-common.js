// Κοινά για αιτήματα, πρότυπα και αξιολογήσεις
import { h, dmy } from "./util.js";

export const CATEGORIES = {
  leave: "Άδεια / απουσία",
  shift_change: "Αλλαγή βάρδιας, ρεπό ή προγράμματος",
  raise: "Αύξηση αποδοχών",
  contract_change: "Αλλαγή ωρών ή σύμβασης",
  advance: "Προκαταβολή",
  documents: "Βεβαιώσεις και έγγραφα",
  transfer: "Μετακίνηση καταστήματος ή αλλαγή θέσης",
  other_hr: "Λοιπό αίτημα προς HR",
  negative_review: "Αρνητική αξιολόγηση",
  incident: "Περιστατικό",
  warning_request: "Αίτημα έγγραφης προειδοποίησης",
};
export const EMPLOYEE_CATS = ["leave", "shift_change", "raise", "contract_change", "advance", "documents", "transfer", "other_hr"];
export const MANAGER_CATS = ["negative_review", "incident", "warning_request"];
export const flowOf = (c) => (c === "leave" ? "leave" : ["raise", "contract_change"].includes(c) ? "gm" : c === "warning_request" ? "warning" : ["negative_review", "incident"].includes(c) ? "report" : "generic");
export const FLOW_NOTE = {
  leave: "Αποφασίζει το HR ή η Γενική Διευθύντρια (η ΓΔ δεν χρειάζεται να περιμένει το HR).",
  gm: "Εξέταση από HR και ΤΕΛΙΚΗ έγκριση από τη Γενική Διευθύντρια. Η έγκριση δεν αλλάζει αυτόματα αποδοχές ή σύμβαση.",
  warning: "Manager → εξέταση & προσχέδιο HR → τελική απόφαση Γενικής Διευθύντριας → κοινοποίηση από HR. Καμία αυτόματη έκδοση.",
  report: "Αναφορά manager προς HR: εξετάζεται και αρχειοθετείται. Δεν αποτελεί έγγραφη προειδοποίηση.",
  generic: "Αποφασίζει το HR ή η Γενική Διευθύντρια. Η έγκριση δεν ενεργοποιεί αυτόματα καμία μεταβολή.",
};

export const REQ_STATUS = {
  draft: { label: "Πρόχειρο", cls: "b-missing" },
  submitted: { label: "Υποβλήθηκε", cls: "b-info" },
  under_review: { label: "Σε εξέταση", cls: "b-info" },
  needs_info: { label: "Απαιτούνται διευκρινίσεις", cls: "b-pending" },
  awaiting_gm: { label: "Αναμονή έγκρισης ΓΔ", cls: "b-pending" },
  approved: { label: "Εγκρίθηκε", cls: "b-signed" },
  rejected: { label: "Απορρίφθηκε", cls: "b-voided" },
  completed: { label: "Ολοκληρώθηκε", cls: "b-done" },
};
export const reqBadge = (s) => `<span class="badge ${REQ_STATUS[s]?.cls || ""}">${REQ_STATUS[s]?.label || h(s)}</span>`;

export const ATTEMPT_STATE = {
  not_started: { label: "Δεν ξεκίνησε", cls: "b-missing" },
  in_progress: { label: "Σε εξέλιξη", cls: "b-info" },
  submitted: { label: "Υποβλήθηκε", cls: "b-signed" },
  pending_manual: { label: "Αναμένει χειροκίνητη βαθμολόγηση", cls: "b-pending" },
  expired: { label: "Έληξε χωρίς υποβολή", cls: "b-voided" },
};
export const attemptBadge = (s) => `<span class="badge ${ATTEMPT_STATE[s]?.cls || ""}">${ATTEMPT_STATE[s]?.label || h(s)}</span>`;

/** Ποιος: 'employee:CODE' → «Ο εργαζόμενος», email → email */
export const who = (x) => (!x ? "—" : String(x).startsWith("employee:") ? `Ο εργαζόμενος (${String(x).slice(9)})` : x);

/** Συμπλήρωση μεταβλητών {όνομα} στο κείμενο προτύπου. Άγνωστες μεταβλητές μένουν ορατές. */
export function renderTemplate(body, vars) {
  return String(body || "").replace(/\{([^{}\s]+)\}/g, (m, k) => (vars[k] !== undefined && vars[k] !== null && vars[k] !== "" ? String(vars[k]) : m));
}
export const daysWord = (n) => (n === null || n === undefined || n === "" ? "" : String(n).replace(".", ",").replace(/,0$/, ""));
export function leaveVars(r, extra = {}) {
  return {
    ονοματεπώνυμο: r.employee_name, κωδικός: r.employee_code, κατάστημα: r.store, κατηγορία: CATEGORIES[r.category],
    είδος_άδειας: r.leave_type_label || "", έναρξη: dmy(r.start_date), λήξη: dmy(r.end_date), ημέρες: daysWord(r.days_requested),
    ημερομηνία_περιστατικού: dmy(r.incident_date), ...extra,
  };
}
export const calendarDays = (a, b) => (a && b && b >= a ? Math.round((Date.parse(b) - Date.parse(a)) / 86400000) + 1 : null);

/** Ώρα Ελλάδας (σωστά με θερινή/χειμερινή ώρα, ανεξάρτητα από τη ζώνη της συσκευής) */
export function athens(ts, withTime = true) {
  if (!ts) return "—";
  return new Date(ts).toLocaleString("el-GR", { timeZone: "Europe/Athens", day: "2-digit", month: "2-digit", year: "numeric", ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}) });
}
/** timestamptz → τιμή για <input type=datetime-local> σε ώρα Ελλάδας */
export function athensInput(ts) {
  if (!ts) return "";
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Athens", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(ts)).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function athensToday() {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Athens", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date()).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day}`;
}

const MIMES = { pdf: "application/pdf", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", heic: "image/heic" };
/** Αρχείο → { name, mime, data(base64) } με έλεγχο τύπου/μεγέθους */
export async function fileToPayload(file) {
  const ext = (file.name.split(".").pop() || "").toLowerCase();
  const mime = MIMES[ext] || file.type;
  if (!Object.values(MIMES).includes(mime)) throw new Error("Επιτρέπονται PDF ή εικόνες (JPG, PNG, WEBP, HEIC).");
  if (file.size > 4 * 1024 * 1024) throw new Error("Το αρχείο ξεπερνά τα 4 MB.");
  const buf = new Uint8Array(await file.arrayBuffer());
  let bin = ""; for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return { name: file.name.slice(0, 200), mime, data: btoa(bin) };
}
export function base64ToBlob(data, mime) {
  const bin = atob(data); const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return new Blob([arr], { type: mime });
}

/** Λόγοι απόρριψης που εφαρμόζονται στο συγκεκριμένο αίτημα */
export function reasonsFor(reasons, r) {
  return reasons.filter((x) => x.active && (r.category === "leave" ? !x.leave_types || x.leave_types.includes(r.leave_type) : x.for_other));
}

export const demoNotice = (what) => `<div class="card empty"><div class="big">⛁</div><strong>${h(what)}</strong>
  <p class="muted" style="margin-top:8px;max-width:520px;margin-inline:auto">Αυτή η ενότητα αποθηκεύει πραγματικά δεδομένα και ελέγχει τα δικαιώματα στον server, γι' αυτό λειτουργεί μόνο με σύνδεση στη βάση (όχι στη λειτουργία επίδειξης).</p></div>`;
