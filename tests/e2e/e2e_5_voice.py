# Φωνητικός Βοηθός AI σε Chrome. Το headless Chrome δεν έχει μικρόφωνο ούτε φωνές, οπότε προσομοιώνονται
# η αναγνώριση ομιλίας (SpeechRecognition) και η ανάγνωση (speechSynthesis). Η απάντηση του AI προσομοιώνεται·
# ελέγχεται ότι η ερώτηση φεύγει με «voice: true» και ότι η απάντηση διαβάζεται χωρίς σύμβολα markdown.
from e2e_common import *

FAKE = r"""
(() => {
  window.__said = []; window.__spoken = []; window.__recStarts = 0;
  class FakeRec {
    constructor() { this.lang = ""; }
    start() { window.__recStarts++; window.__rec = this; window.__recLang = this.lang;
      setTimeout(() => { const t = window.__nextSpeech || ""; if (!t) { this.onerror && this.onerror({ error: "no-speech" }); this.onend && this.onend(); return; }
        const res = [[{ transcript: t }]]; res[0].isFinal = true; this.onresult && this.onresult({ results: res }); this.onend && this.onend(); }, 300); }
    stop() {} abort() { this.onerror && this.onerror({ error: "aborted" }); this.onend && this.onend(); }
  }
  window.webkitSpeechRecognition = FakeRec; window.SpeechRecognition = FakeRec;
  const voices = [{ name: "Microsoft Athina Online (Natural) - Greek (Greece)", lang: "el-GR", voiceURI: "athina" }, { name: "Google Ελληνικά", lang: "el-GR", voiceURI: "g-el" }, { name: "English", lang: "en-US", voiceURI: "en" }];
  const synth = { speaking: false, pending: false, getVoices: () => voices, addEventListener() {}, cancel() { this.speaking = false; window.__cancelled = (window.__cancelled || 0) + 1; },
    speak(u) { this.speaking = true; window.__spoken.push({ text: u.text, voice: u.voice && u.voice.voiceURI, lang: u.lang, rate: u.rate }); setTimeout(() => { this.speaking = false; u.onend && u.onend(); }, 50); } };
  Object.defineProperty(window, "speechSynthesis", { value: synth });
  window.SpeechSynthesisUtterance = function (t) { this.text = t; };
})();
"""

with sync_playwright() as p:
    b = browser(p); pg = new_page(b); pg.context.add_init_script(FAKE)
    asked = []
    def ask(route):
        body = json.loads(route.request.post_data or "{}"); asked.append(body)
        ans = "Λείπουν **3** υπογραφές τον Νοέμβριο: Ελένη Δοκιμή, Κώστας Παράδειγμα και Σάκης Τεστάκης. Σύνολο 1.250 € → 100%." if body.get("voice") else "Λείπουν **3** υπογραφές:\n- Ελένη Δοκιμή\n- Κώστας Παράδειγμα"
        route.fulfill(status=200, content_type="application/json", body=json.dumps({"answer": ans}, ensure_ascii=False))
    pg.route("**/functions/v1/ask", ask)
    login(pg, "owner@test.gr")

    # Πλωτό κουμπί σε άλλη σελίδα
    go(pg, "#/employees")
    check(pg.is_visible("#voice-fab"), "πλωτό κουμπί μικροφώνου σε κάθε σελίδα")
    pg.evaluate("window.__nextSpeech = 'Ποιοι δεν έχουν υπογράψει αυτόν τον μήνα'")
    pg.click("#voice-fab")
    pg.wait_for_selector(".msg.bot >> text=Σάκης Τεστάκης", timeout=8000)
    check("#/assistant" in pg.url and not pg.is_visible("#voice-fab"), "το κουμπί ανοίγει τον Βοηθό και ακούει αμέσως")
    check(pg.evaluate("window.__recLang") == "el-GR", "αναγνώριση ομιλίας στα ελληνικά (el-GR)")
    check(pg.locator(".msg.user").first.inner_text().strip().endswith("Ποιοι δεν έχουν υπογράψει αυτόν τον μήνα") and pg.locator(".msg.user .said").count() == 1, "η φράση γράφεται στη συζήτηση με ένδειξη 🎤")
    check(asked[-1].get("voice") is True, "η φωνητική ερώτηση ζητά από τον server προφορική απάντηση")
    pg.wait_for_function("window.__spoken.length > 0")
    spoken = " ".join(x["text"] for x in pg.evaluate("window.__spoken"))
    check("Σάκης Τεστάκης" in spoken and "*" not in spoken and "€" not in spoken and "ευρώ" in spoken and "τοις εκατό" in spoken, f"η απάντηση διαβάζεται φωναχτά, καθαρή από σύμβολα: «{spoken[:90]}…»")
    check(pg.evaluate("window.__spoken[0].voice") == "athina", "επιλέγεται η πιο φυσική ελληνική φωνή (Natural)")
    shot(pg, "50_voice_answer")

    # Γραπτή ερώτηση: χωρίς ανάγνωση
    n = len(pg.evaluate("window.__spoken"))
    pg.fill("#ai-in", "Και τον Οκτώβριο;"); pg.press("#ai-in", "Enter"); pg.wait_for_selector(".msg.bot >> text=Κώστας Παράδειγμα >> nth=1")
    check(asked[-1].get("voice") is False and len(pg.evaluate("window.__spoken")) == n, "γραπτή ερώτηση: κανονική απάντηση, χωρίς ανάγνωση")
    # Ακρόαση κατά βούληση
    pg.locator(".msg.bot .say").last.click(); pg.wait_for_timeout(300)
    check(len(pg.evaluate("window.__spoken")) > n, "κουμπί 🔊: ακρόαση οποιασδήποτε απάντησης")

    # Ρυθμίσεις φωνής
    pg.click("#ai-vset")
    opts = pg.locator("#vs-voice option").all_inner_texts()
    check(len(opts) == 2 and "English" not in " ".join(opts), "λίστα μόνο με ελληνικές φωνές")
    pg.select_option("#vs-voice", "g-el"); pg.fill("#vs-rate", "1.2"); pg.dispatch_event("#vs-rate", "input")
    pg.click("#vs-test"); pg.wait_for_timeout(300)
    last = pg.evaluate("window.__spoken[window.__spoken.length-1]")
    check(last["voice"] == "g-el" and abs(last["rate"] - 1.2) < 0.01 and "Βοηθός της MEGA GYM" in " ".join(x["text"] for x in pg.evaluate("window.__spoken")), "«Δοκιμή»: ακούγεται με την επιλεγμένη φωνή και ταχύτητα")
    shot(pg, "51_voice_settings")
    pg.reload(); pg.wait_for_selector("#ai-mic"); pg.click("#ai-vset")
    check(pg.input_value("#vs-voice") == "g-el", "οι ρυθμίσεις φωνής θυμούνται")

    # Συνεχής συνομιλία
    pg.check("#vs-hands")
    pg.evaluate("window.__nextSpeech = 'Ποιοι δεν έχουν υπογράψει αυτόν τον μήνα'; window.__recStarts = 0")
    pg.click("#ai-mic"); pg.wait_for_function("window.__recStarts >= 2", timeout=8000)
    check(True, "συνεχής συνομιλία: μετά την ανάγνωση ακούει ξανά")
    pg.evaluate("window.__nextSpeech = ''"); pg.wait_for_selector("#ai-vstat.warn", timeout=5000)
    check("Δεν ακούστηκε" in pg.inner_text("#ai-vstat"), "σιωπή: ήπιο μήνυμα, χωρίς αποστολή")
    pg.uncheck("#vs-hands")

    # Σταμάτημα ανάγνωσης και αλλαγή σελίδας
    pg.evaluate("window.__cancelled = 0")
    go(pg, "#/employees")
    check(pg.evaluate("window.__cancelled") > 0, "αλλαγή σελίδας: σταματά ανάγνωση/μικρόφωνο")

    # Χωρίς υποστήριξη αναγνώρισης (π.χ. Firefox)
    p2 = new_page(b); p2.context.add_init_script("delete window.webkitSpeechRecognition; delete window.SpeechRecognition;")
    login(p2, "owner@test.gr"); go(p2, "#/assistant")
    check(p2.is_disabled("#ai-mic") and "Chrome" in p2.get_attribute("#ai-mic", "title"), "browser χωρίς αναγνώριση: το μικρόφωνο εξηγεί ότι θέλει Chrome/Edge")
    # Ρόλοι
    mg = new_page(b); mg.context.add_init_script(FAKE); login(mg, "glyfada@test.gr")
    check(mg.is_visible("#voice-fab"), "manager: έχει το κουμπί φωνής (όπως και τον Βοηθό)")
    no_js_errors(pg, "ΓΔ φωνή"); no_js_errors(mg, "manager")

print(f"\n{len(RESULTS)} έλεγχοι πέρασαν")
