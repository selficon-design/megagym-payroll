# Φωνή ElevenLabs: ρύθμιση από τη ΓΔ (κλειδί → φωνές → δοκιμή → χρήση για όλους), ανάγνωση απαντήσεων ως αρχείο ήχου,
# εφεδρεία στη φωνή της συσκευής. Το ElevenLabs προσομοιώνεται (η βάση και τα δικαιώματα είναι τα πραγματικά).
from e2e_common import *
import subprocess, struct, io, wave

def sql(q):
    p = subprocess.run(["psql", "-h", "localhost", "-U", "postgres", "-d", "mg_e2e", "-X", "-A", "-t", "-q", "-c", q], capture_output=True, text=True)
    return [l for l in p.stdout.splitlines() if l.strip()]
buf = io.BytesIO(); w = wave.open(buf, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b"\0\0" * 2400); w.close(); WAV = buf.getvalue()

FAKE = r"""(() => {
  window.__spoken = [];
  class R { start() { const t = window.__next || ""; window.__next = ""; setTimeout(() => { const res = [[{ transcript: t }]]; res[0].isFinal = true; if (t) this.onresult && this.onresult({ results: res }); else this.onerror && this.onerror({ error: "no-speech" }); this.onend && this.onend(); }, 150); } stop() {} abort() {} }
  window.webkitSpeechRecognition = R; window.SpeechRecognition = R;
  const synth = { speaking: false, pending: false, getVoices: () => [{ name: "Melina", lang: "el-GR", voiceURI: "melina" }], addEventListener() {}, cancel() {}, resume() {},
    speak(u) { if (!u.text.trim()) { setTimeout(() => u.onend && u.onend(), 5); return; } window.__spoken.push(u.text); u.onstart && u.onstart(); setTimeout(() => u.onend && u.onend(), 20); } };
  Object.defineProperty(window, "speechSynthesis", { value: synth }); window.SpeechSynthesisUtterance = function (t) { this.text = t; };
  const P = HTMLMediaElement.prototype.play; HTMLMediaElement.prototype.play = function () { if (!String(this.src).startsWith("data:")) (window.__played = window.__played || []).push(this.src); return P.call(this); };
})();"""

tts_calls = []; fail = {"on": False}
def tts(route):
    b = json.loads(route.request.post_data or "{}"); tts_calls.append(b)
    if b.get("action") == "status":
        r = sql("select provider || '|' || coalesce(voice_name,'') from voice_settings")[-1].split("|"); k = sql("select count(*) from app_secrets")[-1] == "1"
        return route.fulfill(status=200, content_type="application/json", body=json.dumps({"provider": r[0] if k else "browser", "voice_name": r[1], "model": sql("select model from voice_settings")[-1], "configured": k}, ensure_ascii=False))
    if b.get("action") == "voices":
        return route.fulfill(status=200, content_type="application/json", body=json.dumps({"voices": [{"voice_id": "VoiceMaria01", "name": "Μαρία", "description": "female · greek", "category": "professional"}, {"voice_id": "VoiceNikos02", "name": "Νίκος", "description": "male", "category": "cloned"}]}, ensure_ascii=False))
    if fail["on"]: return route.fulfill(status=502, content_type="application/json", body=json.dumps({"error": "Εξαντλήθηκαν οι χαρακτήρες του λογαριασμού ElevenLabs για αυτόν τον μήνα."}, ensure_ascii=False))
    route.fulfill(status=200, content_type="application/octet-stream", body=WAV)
def ask(route):
    import time; time.sleep(0.4)
    route.fulfill(status=200, content_type="application/json", body=json.dumps({"answer": "Λείπουν δύο υπογραφές: Ελένη Δοκιμή και Κώστας Παράδειγμα.", "timing": {"model_ms": 2100, "tools_ms": 800, "steps": 2, "tools": 2, "prep_ms": 40, "model": "claude-haiku-5-5"}}, ensure_ascii=False))

with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox", "--autoplay-policy=user-gesture-required"])
    pg = new_page(b); pg.context.add_init_script(FAKE); pg.route("**/functions/v1/tts", tts); pg.route("**/functions/v1/ask", ask)
    login(pg, "owner@test.gr"); go(pg, "#/assistant"); pg.click("#ai-vset"); pg.wait_for_selector("#el-key-save")
    check("δεν έχει οριστεί" in pg.inner_text("#el-box"), "ΓΔ: ρύθμιση ElevenLabs στο «⚙ Φωνή» (χωρίς κλειδί ακόμη)")
    pg.fill("#el-key", "sk_e2e_0123456789abcdef0123456789abcdef"); pg.click("#el-key-save")
    pg.wait_for_function("document.querySelector('#el-msg') && document.querySelector('#el-msg').textContent.includes('βρέθηκαν 2 φωνές')", timeout=8000)
    check(sql("select count(*) from app_secrets")[-1] == "1" and pg.input_value("#el-key") == "", "το κλειδί αποθηκεύτηκε στον server και σβήστηκε από την οθόνη")
    check("Νίκος" in pg.inner_text("#el-voice") and "(δική σας)" in pg.inner_text("#el-voice"), "οι φωνές του λογαριασμού ElevenLabs στη λίστα")
    pg.select_option("#el-voice", "VoiceMaria01"); pg.select_option("#el-model", "eleven_flash_v2_5"); pg.click("#el-test")
    pg.wait_for_function("document.querySelector('#el-msg').textContent.includes('ολοκληρώθηκε')", timeout=8000)
    sp = [c for c in tts_calls if c.get("action") == "speak"][-1]
    check(sp.get("voice_id") == "VoiceMaria01" and sp.get("model") == "eleven_flash_v2_5" and pg.evaluate("(window.__played||[]).length") >= 1, "«▶ Δοκιμή»: παίζει η επιλεγμένη φωνή ElevenLabs ως αρχείο ήχου")
    shot(pg, "70_eleven_setup")
    pg.click("#el-use"); pg.wait_for_timeout(800)
    check(sql("select provider || '|' || voice_id || '|' || voice_name || '|' || model from voice_settings")[-1] == "elevenlabs|VoiceMaria01|Μαρία|eleven_flash_v2_5", "«Χρήση για όλους»: ο Βοηθός μιλά με τη «Μαρία»")
    # Φωνητική ερώτηση → απάντηση από ElevenLabs (όχι από τη φωνή του κινητού)
    pg.evaluate("window.__spoken = []; window.__played = []; window.__next = 'Ποιοι δεν έχουν υπογράψει'")
    n0 = len(tts_calls); pg.click("#ai-mic")
    pg.wait_for_function("(window.__played||[]).length >= 1", timeout=10000)
    sp = [c for c in tts_calls[n0:] if c.get("action") == "speak"]
    check(sp and "Ελένη Δοκιμή" in sp[0]["text"] and "voice_id" not in {k for k, v in sp[0].items() if v}, "η απάντηση διαβάζεται από το ElevenLabs με τη φωνή που όρισε η ΓΔ")
    check(pg.evaluate("window.__spoken.length") == 0, "δεν χρησιμοποιείται η φωνή της συσκευής")
    pg.wait_for_function("[...document.querySelectorAll('.msg .tm')].some(e => e.textContent.includes('σύνολο'))", timeout=8000)
    tm = pg.locator(".msg .tm").last.inner_text()
    check(all(x in tm for x in ("ακρόαση", "AI", "σκέψη μοντέλου 2,1″", "2 αναζητήσεις στα δεδομένα 0,8″", "φωνή", "ElevenLabs Flash", "σύνολο")), f"χρόνοι κάτω από την απάντηση: «{tm}»")
    shot(pg, "71_timings")
    pg.wait_for_function("document.querySelector('#ai-mic').dataset.state === 'idle'", timeout=10000)
    check(True, "μετά το τέλος του ήχου το μικρόφωνο είναι ξανά έτοιμο")
    # Εφεδρεία
    fail["on"] = True; pg.evaluate("window.__spoken = []; window.__next = 'Και τον Οκτώβριο;'")
    pg.click("#ai-mic"); pg.wait_for_function("window.__spoken.length > 0", timeout=10000)
    pg.wait_for_selector(".toast", timeout=5000)
    check("Εξαντλήθηκαν" in pg.inner_text("body"), "αν το ElevenLabs αποτύχει: διαβάζει η φωνή της συσκευής και εξηγεί γιατί")
    fail["on"] = False
    # Manager: χρησιμοποιεί τη φωνή, δεν τη ρυθμίζει
    mg = new_page(b); mg.context.add_init_script(FAKE); mg.route("**/functions/v1/tts", tts); login(mg, "glyfada@test.gr"); go(mg, "#/assistant"); mg.click("#ai-vset"); mg.wait_for_timeout(800)
    check("ElevenLabs — Μαρία" in mg.inner_text("#el-box") and mg.locator("#el-key").count() == 0, "manager: βλέπει τη φωνή, χωρίς πρόσβαση στο κλειδί")
    no_js_errors(pg, "ΓΔ ElevenLabs"); no_js_errors(mg, "manager")
print(f"\n{len(RESULTS)} έλεγχοι πέρασαν")
