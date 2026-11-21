// Ταμεία · κοινά βοηθητικά (εφαρμογή και σύνδεσμος ρεσεψιόν)

export const SHIFT_GR = { morning: "Πρωινό (16:00)", evening: "Βραδινό", supplement: "Συμπληρωματικό" };
export const SHIFT_SHORT = { morning: "Π", evening: "Β", supplement: "Σ" };
export const STATUS_GR = {
  open: { label: "Ανοιχτή", cls: "b-missing" },
  confirmed: { label: "Επιβεβαιώθηκε · προς λογιστήριο", cls: "b-pending" },
  locked: { label: "Ελέγχθηκε · κλειδωμένη", cls: "b-signed" },
  correction: { label: "Σε διόρθωση", cls: "b-voided" },
};
export const METHOD_GR = { cash: "Μετρητά", card: "Κάρτα" };
export const REFUND_GR = { pending: { label: "Περιμένει έγκριση", cls: "b-pending" }, approved: { label: "Εγκρίθηκε", cls: "b-signed" }, rejected: { label: "Απορρίφθηκε", cls: "b-voided" } };
export const ADJ_GR = { cash: "Μετρητά", cards: "Κάρτες", iris: "IRIS" };

export const h = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
export const $ = (s, el = document) => el.querySelector(s);
export const $$ = (s, el = document) => [...el.querySelectorAll(s)];

export function eur(n, { sign = false } = {}) {
  if (n === null || n === undefined || n === "") return "—";
  const v = Number(n);
  const s = Math.abs(v).toLocaleString("el-GR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
  return v < 0 ? "−" + s : sign && v > 0 ? "+" + s : s;
}
/** "1.250,50" / "1250.5" / "1250,5" → 1250.5 · κενό → null · λάθος → NaN */
export function amount(v, { signed = false } = {}) {
  let s = String(v ?? "").trim().replace(/\s|€/g, "");
  if (!s) return null;
  const neg = signed && /^[-−]/.test(s);
  s = s.replace(/^[-−]/, "");
  if (/^\d{1,3}(\.\d{3})+(,\d{1,2})?$/.test(s)) s = s.replace(/\./g, "").replace(",", ".");
  else s = s.replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return NaN;
  const n = Number(s);
  return n >= 1000000 ? NaN : neg ? -n : n;
}
export const dmy = (iso) => { const [y, m, d] = String(iso || "").slice(0, 10).split("-"); return d ? `${d}/${m}/${y}` : ""; };
const DAYS = ["Κυριακή", "Δευτέρα", "Τρίτη", "Τετάρτη", "Πέμπτη", "Παρασκευή", "Σάββατο"];
export const dayName = (iso) => DAYS[new Date(iso + "T12:00:00").getDay()];
export const athensTime = (ts) => ts ? new Date(ts).toLocaleString("el-GR", { timeZone: "Europe/Athens", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "";
export const isoDate = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
export const addDays = (iso, n) => { const d = new Date(iso + "T12:00:00"); d.setDate(d.getDate() + n); return isoDate(d); };

// Διαφορά με χρώμα: 0 = πράσινο, αλλιώς κόκκινο
export function diffCell(v) {
  if (v === null || v === undefined) return `<span class="muted">—</span>`;
  const n = Number(v);
  return `<span class="num ${Math.abs(n) < 0.005 ? "t-ok" : "t-bad"}">${eur(n, { sign: true })}</span>`;
}

// Φωτογραφία παραστατικού: σμίκρυνση σε JPEG (έως 1600px) πριν από την αποστολή — μικρό αρχείο, γρήγορη υποβολή
export async function readReceipt(file) {
  if (!file) return null;
  if (file.type === "application/pdf") {
    if (file.size > 4 * 1024 * 1024) throw new Error("Το PDF ξεπερνά τα 4 MB.");
    return { name: file.name, mime: file.type, data: await toBase64(file) };
  }
  if (!/^image\//.test(file.type)) throw new Error("Επιλέξτε φωτογραφία ή PDF.");
  try {
    const bmp = await createImageBitmap(file);
    const k = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
    const c = document.createElement("canvas");
    c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k);
    c.getContext("2d").drawImage(bmp, 0, 0, c.width, c.height);
    const blob = await new Promise((res) => c.toBlob(res, "image/jpeg", 0.82));
    return { name: (file.name || "parastatiko").replace(/\.\w+$/, "") + ".jpg", mime: "image/jpeg", data: await toBase64(blob) };
  } catch {
    if (file.size > 4 * 1024 * 1024) throw new Error("Η φωτογραφία ξεπερνά τα 4 MB.");
    return { name: file.name, mime: file.type, data: await toBase64(file) };
  }
}
function toBase64(blob) {
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result).replace(/^data:[^,]*,/, "")); r.onerror = () => rej(new Error("Δεν διαβάστηκε το αρχείο.")); r.readAsDataURL(blob); });
}

const loaded = {};
export function loadScript(src) {
  return (loaded[src] ??= new Promise((res, rej) => {
    const s = document.createElement("script");
    s.src = src; s.onload = res; s.onerror = () => rej(new Error("Δεν φορτώθηκε η σελίδα. Ελέγξτε τη σύνδεση και ανανεώστε."));
    document.head.append(s);
  }));
}

export function friendly(err) {
  const m = String(err?.message || err || "");
  if (/Invalid login credentials/i.test(m)) return "Λάθος email ή κωδικός.";
  if (/permission denied|row-level security/i.test(m)) return "Δεν έχετε δικαίωμα για αυτή την ενέργεια.";
  if (/Failed to fetch|NetworkError|network/i.test(m)) return "Δεν υπάρχει σύνδεση στο internet. Δοκιμάστε ξανά.";
  if (/JWT|expired/i.test(m)) return "Η σύνδεση έληξε. Συνδεθείτε ξανά.";
  return m || "Προέκυψε σφάλμα.";
}
