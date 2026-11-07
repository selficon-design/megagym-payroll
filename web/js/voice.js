// Φωνή για τον Βοηθό AI: αναγνώριση ομιλίας (ελληνικά) και ανάγνωση απαντήσεων.
// Πάροχος «browser»: Web Speech API (Chrome/Edge). Η ανάγνωση περνά από τη speak(), ώστε αργότερα
// να μπορεί να προστεθεί εξωτερικός πάροχος φωνής (π.χ. ElevenLabs) χωρίς αλλαγές στην οθόνη.

const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
const synth = window.speechSynthesis;
const KEY = "mg-voice";
const DEF = { speak: true, hands: false, voice: "", rate: 1 };

export const canListen = !!SR;
export const canSpeak = !!synth && typeof SpeechSynthesisUtterance !== "undefined";

export function prefs() {
  try { return { ...DEF, ...(JSON.parse(localStorage.getItem(KEY) || "{}")) }; } catch { return { ...DEF }; }
}
export function setPrefs(p) {
  const next = { ...prefs(), ...p };
  try { localStorage.setItem(KEY, JSON.stringify(next)); } catch {}
  return next;
}

/** Ελληνικές φωνές του υπολογιστή/browser (οι πιο φυσικές πρώτα). */
export function greekVoices() {
  if (!canSpeak) return [];
  const score = (v) => (/natural|online|neural/i.test(v.name) ? 0 : /google/i.test(v.name) ? 1 : 2);
  return synth.getVoices().filter((v) => /^el(-|_|$)/i.test(v.lang)).sort((a, b) => score(a) - score(b) || a.name.localeCompare(b.name));
}
/** Οι φωνές φορτώνουν ασύγχρονα στον Chrome. */
export function onVoicesReady(fn) {
  if (!canSpeak) return;
  if (synth.getVoices().length) fn();
  synth.addEventListener?.("voiceschanged", fn, { once: true });
}
function pickVoice() {
  const list = greekVoices(), want = prefs().voice;
  return list.find((v) => v.voiceURI === want) || list[0] || null;
}

// ─────────────── Ομιλία → κείμενο ───────────────
const ERR = {
  "not-allowed": "Ο browser δεν επιτρέπει το μικρόφωνο. Πατήστε το εικονίδιο 🔒 δίπλα στη διεύθυνση και επιτρέψτε το «Μικρόφωνο».",
  "service-not-allowed": "Ο browser δεν επιτρέπει την αναγνώριση ομιλίας σε αυτή τη σελίδα.",
  "audio-capture": "Δεν βρέθηκε μικρόφωνο. Ελέγξτε ότι είναι συνδεδεμένο.",
  network: "Η αναγνώριση ομιλίας χρειάζεται σύνδεση στο internet.",
  "no-speech": "Δεν ακούστηκε τίποτα. Πατήστε ξανά το μικρόφωνο και μιλήστε.",
  "language-not-supported": "Ο browser δεν υποστηρίζει αναγνώριση ελληνικών.",
};
let rec = null;
/**
 * Ακούει μία φράση στα ελληνικά. Επιστρέφει συνάρτηση διακοπής.
 * onText(κείμενο, τελικό) · onEnd(τελικό κείμενο) · onError(μήνυμα)
 */
export function listen({ onText, onEnd, onError, continuous = false, silenceMs = 2500 } = {}) {
  if (!canListen) { onError?.("Η φωνητική εντολή λειτουργεί σε Google Chrome ή Microsoft Edge."); return () => {}; }
  stopListening();
  stopSpeaking();
  const r = new SR();
  // continuous: για μεγάλες εξηγήσεις με παύσεις — σταματά μετά από silenceMs σιωπής (ή με το κουμπί)
  r.lang = "el-GR"; r.interimResults = true; r.continuous = !!continuous; r.maxAlternatives = 1;
  let final = "", failed = false, quiet;
  r.onresult = (e) => {
    let interim = ""; final = "";
    for (const res of e.results) (res.isFinal ? (final += res[0].transcript + " ") : (interim += res[0].transcript));
    final = final.replace(/\s+/g, " ");
    onText?.((final + interim).trim(), !interim);
    if (continuous) { clearTimeout(quiet); quiet = setTimeout(() => { try { r.stop(); } catch {} }, silenceMs); }
  };
  r.onerror = (e) => { if (e.error === "no-speech") return; failed = true; if (e.error === "aborted") return; onError?.(ERR[e.error] || "Η αναγνώριση ομιλίας σταμάτησε (" + e.error + ")."); };
  r.onend = () => { clearTimeout(quiet); if (rec === r) rec = null; if (!failed) onEnd?.(final.trim()); };
  rec = r;
  try { r.start(); } catch (e) { rec = null; onError?.("Δεν ξεκίνησε το μικρόφωνο: " + e.message); }
  return () => { try { r.stop(); } catch {} };
}
export function stopListening() { if (rec) { try { rec.abort(); } catch {} rec = null; } }
export const isListening = () => !!rec;

// ─────────────── Κείμενο → ομιλία ───────────────
/** Markdown της απάντησης → καθαρό προφορικό κείμενο. */
export function toSpeech(md) {
  return String(md || "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/^\s*\|?\s*:?-{2,}.*$/gm, "")                           // γραμμές διαχωρισμού πινάκων
    .replace(/\|/g, ", ")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_`#>]+/g, "")
    .replace(/^\s*[-•·]\s+/gm, "")
    .replace(/ΑΙ-(\d{4})-0*(\d+)/g, "αίτημα $2")
    .replace(/→/g, " προς ").replace(/€/g, " ευρώ").replace(/%/g, " τοις εκατό")
    .replace(/(\d)\.(\d{3})(?!\d)/g, "$1$2")                          // 1.250 → 1250
    .replace(/\n{2,}/g, ". ").replace(/\n/g, ". ")
    .replace(/\s*\.\s*(\.\s*)+/g, ". ").replace(/\s{2,}/g, " ").trim();
}
/** Μικρά κομμάτια (ο Chrome κόβει τις μεγάλες εκφωνήσεις). */
function chunks(text) {
  const out = []; let cur = "";
  for (const s of text.match(/[^.;!?·]+[.;!?·]*\s*/g) || [text]) {
    if ((cur + s).length > 220 && cur) { out.push(cur.trim()); cur = ""; }
    cur += s;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}
let speakId = 0;
/** Διαβάζει κείμενο. Επιστρέφει Promise που ολοκληρώνεται στο τέλος (ή όταν διακοπεί). */
export function speak(text, { onStart, onEnd } = {}) {
  if (!canSpeak) { onEnd?.(); return Promise.resolve(); }
  stopSpeaking();
  const id = ++speakId, parts = chunks(toSpeech(text)), v = pickVoice(), rate = Number(prefs().rate) || 1;
  return new Promise((resolve) => {
    const done = () => { if (id === speakId) onEnd?.(); resolve(); };
    if (!parts.length) return done();
    onStart?.();
    let i = 0;
    const next = () => {
      if (id !== speakId) return resolve();
      if (i >= parts.length) return done();
      const u = new SpeechSynthesisUtterance(parts[i++]);
      u.lang = v?.lang || "el-GR"; if (v) u.voice = v; u.rate = rate; u.pitch = 1;
      u.onend = next; u.onerror = (e) => (e.error === "interrupted" || e.error === "canceled" ? resolve() : next());
      synth.speak(u);
    };
    next();
  });
}
export function stopSpeaking() { speakId++; if (canSpeak) synth.cancel(); }
export const isSpeaking = () => canSpeak && (synth.speaking || synth.pending);
