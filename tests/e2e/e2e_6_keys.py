# Σωστές απαντήσεις με φωνή → επιβεβαίωση → ενεργοποίηση · παραδείγματα βαθμολόγησης με φωνή · αξιολογήσεις AI.
# Προσομοιώνονται το μικρόφωνο/η φωνή του browser και οι απαντήσεις του AI (η βάση και τα δικαιώματα είναι τα πραγματικά).
from e2e_common import *
import subprocess, datetime

def sql(q, as_email=None, anon=False):
    pre = f"select set_config('request.jwt.claims', '{json.dumps({'email': as_email})}', false) \\g /dev/null\nset role authenticated;\n" if as_email else ("set role anon;\n" if anon else "")
    p = subprocess.run(["psql", "-h", "localhost", "-U", "postgres", "-d", "mg_e2e", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"], input=pre + q + ";\n", capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return [l for l in p.stdout.splitlines() if l.strip()]
def ath(m): return (datetime.datetime.now(datetime.UTC).replace(tzinfo=None) + datetime.timedelta(hours=2, minutes=m)).strftime("%Y-%m-%d %H:%M")
OWNER = "owner@test.gr"

Q = sql("select (q_create('Γνώσεις προσωπικού (e2e)', null))->>'id'", OWNER)[-1]
sql(f"""select q_save_questions('{Q}', '[
 {{"row":2,"specialty":"","section":"Ασφάλεια","text":"Τι κάνετε αν ένας πελάτης ζαλιστεί;","type":"Μία επιλογή","options":["Συνεχίζει","Σταματώ και τον καθίζω","Ενεργειακό ποτό"],"correct":"","points":"","required":"Ναι","order":"1"}},
 {{"row":3,"specialty":"","section":"Ασφάλεια","text":"Τι ελέγχετε κάθε πρωί;","type":"Πολλές επιλογές","options":["Καλώδια","Συρματόσχοινα","Χρώμα"],"correct":"","points":"","required":"Ναι","order":"2"}},
 {{"row":4,"specialty":"","section":"Εξυπηρέτηση","text":"Πώς προτείνετε προσωπική προπόνηση;","type":"Ελεύθερο κείμενο","options":[],"correct":"","points":"","required":"Ναι","order":"3"}}
]', 'e2e.xlsx')""", OWNER)
sql(f"select q_update_meta('{Q}', 'Γνώσεις προσωπικού (e2e)', null, '{{Ρεσεψιόν,Επίβλεψη}}', null)", OWNER)
sql(f"select q_set_window('{Q}', '{ath(-60)}', '{ath(60*24*5)}', null)", OWNER)
sql(f"select q_publish('{Q}')", OWNER)
c = json.loads(sql(f"select link_create('{Q}', '{{T100,T101,T200}}', '{ath(-60)}', '{ath(600)}')", OWNER)[-1])
qid = dict((r.split("|")[0], r.split("|")[1]) for r in sql(f"select row_no || '|' || x.id from assessment_questions x join questionnaires q on q.current_version_id = x.version_id where q.id = '{Q}'"))
ANS = {"T100": "Ρωτάω στόχους και κλείνω δωρεάν δοκιμαστική.", "T101": "Του λέω ότι είναι ακριβή αλλά αξίζει.", "T200": "Του δίνω φυλλάδιο."}
for r in c["rows"]:
    sql(f"select link_get('{r['token']}')", anon=True)
    sql(f"""select link_submit('{r['token']}', '{json.dumps({qid['2']: 'Β', qid['3']: ['Α'], qid['4']: ANS[r['employee_code']]}, ensure_ascii=False)}')""", anon=True)

FAKE = r"""(() => {
  window.__q = []; window.__spoken = [];
  class R { start() { const t = window.__q.shift() || ""; setTimeout(() => { if (!t) { this.onerror && this.onerror({ error: "no-speech" }); this.onend && this.onend(); return; }
      const res = [[{ transcript: t }]]; res[0].isFinal = true; this.onresult && this.onresult({ results: res }); this.onend && this.onend(); }, 150); }
    stop() {} abort() { this.onerror && this.onerror({ error: "aborted" }); this.onend && this.onend(); } }
  window.webkitSpeechRecognition = R; window.SpeechRecognition = R;
  const synth = { speaking: false, pending: false, getVoices: () => [{ name: "Greek", lang: "el-GR", voiceURI: "el" }], addEventListener() {}, cancel() {},
    speak(u) { if (!u.text.trim()) { setTimeout(() => u.onend && u.onend(), 5); return; } window.__spoken.push(u.text); setTimeout(() => u.onend && u.onend(), 20); } };
  Object.defineProperty(window, "speechSynthesis", { value: synth }); window.SpeechSynthesisUtterance = function (t) { this.text = t; };
})();"""

calls = []
def ai(route):
    b = json.loads(route.request.post_data or "{}"); calls.append(b); m = b.get("mode")
    if m == "key":
        s = b["spoken"]
        r = {"correct": ["Β"], "model_answer": None, "confidence": "high", "note": None, "spoken_summary": "Β, σταματώ και τον καθίζω."} if "δεύτερο" in s else \
            {"correct": ["Α", "Β"], "model_answer": None, "confidence": "medium", "note": "Ελέγξτε αν μετρά και το Γ.", "spoken_summary": "Α και Β."} if "α και β" in s else \
            {"correct": None, "model_answer": "Ρωτάμε στόχους, προτείνουμε δωρεάν δοκιμαστική. Ποτέ σχόλια για τιμή ή σώμα.", "confidence": "high", "note": None, "spoken_summary": "Κράτησα τρία σημεία."}
    elif m == "rate":
        r = {"score": 8 if "οκτώ" in b["spoken"] else 3, "reason": "Καλά: δοκιμαστική. Έλειπαν οι στόχοι." if "οκτώ" in b["spoken"] else "Δεν λέμε «ακριβή».", "spoken_summary": "Καταχωρήθηκε."}
    else:
        r = {"items": [{"attempt_id": it["attempt_id"], "score": 2 if "φυλλάδιο" in it["answer"] else 9, "reason": "Χωρίς ερώτηση στόχων ή δοκιμαστική." if "φυλλάδιο" in it["answer"] else "Ταιριάζει με την πρότυπη."} for it in b["items"]], "examples_used": 2, "model": "test"}
    route.fulfill(status=200, content_type="application/json", body=json.dumps(r, ensure_ascii=False))

with sync_playwright() as p:
    b = browser(p); gm = new_page(b); gm.context.add_init_script(FAKE); gm.route("**/functions/v1/answer-key", ai)
    login(gm, OWNER)
    # ══ 1. Σωστές απαντήσεις με φωνή ══
    go(gm, f"#/assessment?id={Q}&tab=keys")
    check("Χωρίς απάντηση3" in gm.inner_text("#view"), "καρτέλα «Σωστές απαντήσεις»: 3 ερωτήσεις χωρίς σωστή απάντηση")
    gm.click("#ky-begin"); gm.wait_for_selector("#ky-voice")
    check("πρόχειρη έκδοση 2" in gm.inner_text("#view"), "δημιουργήθηκε πρόχειρη έκδοση 2 (η ενεργή δεν επηρεάζεται)")
    gm.evaluate("window.__q = ['το δεύτερο, σταματάω το μηχάνημα', 'α και β', 'πρώτα ρωτάς τους στόχους, μετά δωρεάν δοκιμαστική, ποτέ για τιμή']")
    gm.click("#ky-voice"); gm.wait_for_selector(".vr-q")
    shot(gm, "60_keys_voice")
    gm.wait_for_selector("#dlg:not([open])", state="attached", timeout=15000)
    spoken = " ".join(gm.evaluate("window.__spoken"))
    check("Τι κάνετε αν ένας πελάτης ζαλιστεί" in spoken and "Β: Σταματώ και τον καθίζω" in spoken, "ο Βοηθός διάβασε ερώτηση και επιλογές")
    check([x["spoken"] for x in calls if x.get("mode") == "key"] == ["το δεύτερο, σταματάω το μηχάνημα", "α και β", "πρώτα ρωτάς τους στόχους, μετά δωρεάν δοκιμαστική, ποτέ για τιμή"], "κάθε προφορική απάντηση πήγε στο AI με τη σωστή ερώτηση")
    gm.select_option("#ky-show", "all"); gm.wait_for_timeout(400)
    t = gm.inner_text("#view")
    check(t.count("Κατ' εκτίμηση") >= 3 and "Β. Σταματώ και τον καθίζω" in t and "Ρωτάμε στόχους" in t and "Ελέγξτε αν μετρά και το Γ" in t, "λίστα: 3 απαντήσεις κατ' εκτίμηση, με σημείωση του AI όπου χρειάζεται")
    shot(gm, "61_keys_list")
    go(gm, f"#/assessment?id={Q}&tab=settings")
    check("κατ' εκτίμηση" in gm.inner_text("#view") and gm.is_disabled("#qs-pub"), "η ενεργοποίηση μπλοκάρεται μέχρι να επιβεβαιωθούν οι εκτιμήσεις")
    go(gm, f"#/assessment?id={Q}&tab=keys"); gm.select_option("#ky-show", "estimate"); gm.wait_for_timeout(300)
    gm.locator("tr[data-id]", has_text="Τι ελέγχετε").locator("[data-ed]").click(); gm.wait_for_selector("#ek-ok")
    gm.uncheck('input[name="ek-c"][value="Β"]'); gm.click("#ek-ok"); gm.wait_for_timeout(500)
    gm.click("#ky-confirm-all"); gm.click("#cb-ok"); gm.wait_for_timeout(600)
    gm.fill("#ky-pts", "2"); gm.click("#ky-pts-ok"); gm.wait_for_timeout(500)
    r = sql(f"select string_agg(row_no || ':' || coalesce(correct::text,'-') || ':' || coalesce(points::text,'-') || ':' || key_status, ' ' order by row_no) from assessment_questions x join questionnaire_versions v on v.id = x.version_id where v.questionnaire_id = '{Q}' and v.status = 'draft'")[-1]
    check(r == '2:["Β"]:2.00:confirmed 3:["Α"]:2.00:confirmed 4:-:-:confirmed', f"διόρθωση + επιβεβαίωση + βαθμοί ({r})")
    go(gm, f"#/assessment?id={Q}&tab=settings")
    check("κανόνα βαθμολόγησης" in gm.inner_text("#view"), "με βαθμούς σε «πολλές επιλογές» ζητείται κανόνας βαθμολόγησης")
    gm.select_option("#qs-rule", "all_or_nothing"); gm.wait_for_timeout(900)
    gm.click("#qs-pub"); gm.click("#cb-ok"); gm.wait_for_timeout(800)
    check(sql(f"select v.version from questionnaires q join questionnaire_versions v on v.id = q.current_version_id where q.id = '{Q}'")[-1] == "2", "ενεργοποίηση έκδοσης 2 με τις σωστές απαντήσεις")

    # ══ 2. Παραδείγματα βαθμολόγησης με φωνή ══
    go(gm, f"#/assessment?id={Q}&tab=examples")
    check(gm.locator(".ex-row").count() == 3, "παραδείγματα: οι 3 απαντήσεις ελεύθερου κειμένου των εργαζομένων")
    gm.evaluate("window.__spoken = []; window.__q = ['οκτώ, γιατί έκλεισε δοκιμαστική αλλά δεν ρώτησε στόχους', 'τρία, δεν λέμε ποτέ ακριβή', 'επόμενη']")
    gm.click("#ex-voice"); gm.wait_for_selector(".vr-ans")
    shot(gm, "62_examples_voice")
    gm.wait_for_selector("#dlg:not([open])", state="attached", timeout=15000)
    spoken = " ".join(gm.evaluate("window.__spoken"))
    check("Απάντηση εργαζομένου" in spoken and "Δοκιμή" not in spoken and "Τεστάκης" not in spoken, "διαβάζεται η απάντηση χωρίς όνομα εργαζομένου")
    ex = sql(f"select string_agg(score::text || ':' || source, ',' order by score) from answer_examples where questionnaire_id = '{Q}'")[-1]
    check(ex == "3.0:voice,8.0:voice", f"δύο παραδείγματα με βαθμό και λόγο· η «επόμενη» παρέλειψε την τρίτη ({ex})")
    gm.select_option("#ex-show", "done"); gm.wait_for_timeout(400)
    vals = gm.evaluate("[...document.querySelectorAll('.ex-r')].map(t => t.value).join(' | ')")
    check("Δεν λέμε «ακριβή»" in vals and gm.locator(".ex-s").first.input_value() in ("8", "3"), "ο βαθμός και ο λόγος φαίνονται και διορθώνονται στη λίστα")

    # ══ 3. Αξιολογήσεις AI ══
    go(gm, f"#/assessment?id={Q}&tab=evals")
    check("2 παραδείγματα βαθμολόγησης" in gm.inner_text("#view"), "αξιολογήσεις: η ερώτηση έχει σωστή απάντηση και 2 παραδείγματα")
    gm.click("[data-evq]"); gm.wait_for_selector("[data-acc]")
    ev_call = [x for x in calls if x.get("mode") == "evaluate"][-1]
    check(len(ev_call["items"]) == 1 and "φυλλάδιο" in ev_call["items"][0]["answer"], "το AI αξιολογεί μόνο όσες δεν βαθμολογήσατε εσείς")
    shot(gm, "63_evals")
    gm.click("[data-cor]"); gm.fill("#ec-s", "1"); gm.fill("#ec-r", "Ούτε στόχοι ούτε δοκιμαστική."); gm.click("#ec-ok"); gm.wait_for_timeout(800)
    check(sql(f"select score::text || ':' || source from answer_examples where questionnaire_id = '{Q}' and answer_text like '%φυλλάδιο%'")[-1] == "1.0:correction", "διόρθωση → νέο παράδειγμα για να μάθει το AI")
    gm.select_option("#ev-show", "all"); gm.wait_for_timeout(400)
    check("απείχε κατά μέσο όρο" in gm.inner_text("#view"), "ένδειξη ακρίβειας του AI σε σχέση με τους βαθμούς σας")
    no_js_errors(gm, "ΓΔ σωστές απαντήσεις / παραδείγματα / αξιολογήσεις")

    # Χωρίς πρόσβαση για manager
    mg = new_page(b); login(mg, "glyfada@test.gr"); go(mg, f"#/assessment?id={Q}&tab=keys")
    check("Σωστές απαντήσεις" not in mg.inner_text("#view"), "manager: δεν βλέπει σωστές απαντήσεις/παραδείγματα")

print(f"\n{len(RESULTS)} έλεγχοι πέρασαν")
