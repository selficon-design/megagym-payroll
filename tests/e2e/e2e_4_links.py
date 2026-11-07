# Προσωπικοί σύνδεσμοι αξιολόγησης σε πραγματικό Chrome: δημιουργία από ΓΔ, άνοιγμα στον υπολογιστή καταστήματος,
# αποσύνδεση διαχείρισης, προσωρινή αποθήκευση/διακοπή σύνδεσης, μία υποβολή, χρονικά όρια, ακύρωση/επανέκδοση,
# απομόνωση, καρτέλα εργαζομένου. Μόνο εικονικά στοιχεία (βάση mg_e2e).
from e2e_common import *
import subprocess, datetime

def sql(q, as_email=None):
    pre = f"select set_config('request.jwt.claims', '{json.dumps({'email': as_email})}', false) \\g /dev/null\nset role authenticated;\n" if as_email else ""
    p = subprocess.run(["psql", "-h", "localhost", "-U", "postgres", "-d", "mg_e2e", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"], input=pre + q + ";\n", capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return [l for l in p.stdout.splitlines() if l.strip()]
def ath(delta_min):
    t = datetime.datetime.now(datetime.UTC).replace(tzinfo=None) + datetime.timedelta(hours=2, minutes=delta_min)   # Νοέμβριος: UTC+2
    return t.strftime("%Y-%m-%d %H:%M")
def dl(delta_min): return ath(delta_min).replace(" ", "T")
def fresh(pg, hash):
    go(pg, hash); pg.evaluate("window.dispatchEvent(new Event('mg:rerender'))"); pg.wait_for_timeout(500); pg.wait_for_load_state("networkidle")
OWNER = "owner@test.gr"

# Ερωτηματολόγιο (υπάρχουσα ροή: Excel → πρόχειρο → ενεργοποίηση)
Q = sql("select (q_create('Αξιολόγηση Νοεμβρίου (e2e)', 'Σύντομο ερωτηματολόγιο δοκιμής.'))->>'id'", OWNER)[-1]
sql(f"""select q_save_questions('{Q}', '[
 {{"row":2,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Τι σημαίνει DR;","type":"Μία επιλογή","options":["Άμεση εγγραφή","Δοκιμαστικό","Χαμένη ενημέρωση"],"correct":"Α","points":"2","required":"Ναι","order":"1"}},
 {{"row":3,"specialty":"Ρεσεψιόν","section":"Αυτοαξιολόγηση","text":"Πόσο άνετα χειρίζεστε τα τηλέφωνα;","type":"Κλίμακα","options":["1","5","Καθόλου","Πολύ"],"correct":"","points":"","required":"Ναι","order":"2"}},
 {{"row":4,"specialty":"","section":"Γενικά","text":"Σχόλια για την εκπαίδευση","type":"Ελεύθερο κείμενο","options":[],"correct":"","points":"","required":"Όχι","order":"3"}},
 {{"row":5,"specialty":"Επίβλεψη","section":"Γενικά","text":"Ελέγχετε τα όργανα κάθε πρωί;","type":"Μία επιλογή","options":["Ναι","Όχι"],"correct":"Α","points":"1","required":"Ναι","order":"4"}}
]', 'e2e.xlsx')""", OWNER)
sql(f"select q_update_meta('{Q}', 'Αξιολόγηση Νοεμβρίου (e2e)', 'Σύντομο ερωτηματολόγιο δοκιμής.', '{{Ρεσεψιόν,Επίβλεψη}}', null)", OWNER)
sql(f"select q_set_window('{Q}', '{ath(-60)}', '{ath(60 * 24 * 5)}', 'e2e')", OWNER)
assert sql(f"select (q_publish('{Q}'))->>'ok'", OWNER)[-1] == "true"

with sync_playwright() as p:
    b = browser(p)
    # ══ 1. ΓΔ: δημιουργία προσωπικών συνδέσμων ══
    gm = new_page(b); gm.context.grant_permissions(["clipboard-read", "clipboard-write"], origin=BASE.rstrip("/"))
    login(gm, OWNER); go(gm, f"#/assessment?id={Q}&tab=links")
    check("Δεν έχουν δημιουργηθεί προσωπικοί σύνδεσμοι" in gm.inner_text("#view"), "ΓΔ: καρτέλα «Προσωπικοί σύνδεσμοι» στο ερωτηματολόγιο")
    gm.click("#lk-new"); gm.wait_for_selector("#nl-list")
    check(gm.locator("#nl-list input").count() == 3, "λίστα συμμετεχόντων: ενεργοί των ειδικοτήτων (Ρεσεψιόν, Επίβλεψη)")
    gm.click("#nl-none"); gm.fill("#nl-s", dl(-60)); gm.fill("#nl-e", dl(60 * 24 * 2))
    for code in ("T100", "T200", "T101"): gm.check(f'#nl-list input[value="{code}"]')
    shot(gm, "40_links_create"); gm.click("#nl-ok")
    gm.wait_for_selector("text=Δημιουργήθηκαν 3 σύνδεσμοι")
    urls = gm.locator("#dlg td.small").all_inner_texts()
    check(len(urls) == 3 and all("/a.html#" in u for u in urls), "3 διαφορετικοί σύνδεσμοι (a.html#κλειδί)")
    check(len(set(urls)) == 3 and not any(c in u for u in urls for c in ("T100", "T200", "T101", "Δοκιμή")), "οι σύνδεσμοι δεν περιέχουν κωδικό ή όνομα εργαζομένου")
    names = gm.locator("#dlg td strong").all_inner_texts()
    L = dict(zip(names, urls))
    shot(gm, "41_links_created"); gm.click("#rs-copy"); gm.wait_for_timeout(200)
    clip = gm.evaluate("navigator.clipboard.readText()")
    check(all(u in clip for u in urls) and "Ελένη Δοκιμή · Γλυφάδα" in clip, "«Αντιγραφή όλων»: λίστα όνομα · κατάστημα · σύνδεσμος")
    gm.click("#dlg [data-close]"); gm.wait_for_timeout(600)
    check(gm.locator("tr[data-id]").count() == 3 and gm.inner_text("#view").count("Έτοιμος · δεν άνοιξε") >= 3, "λίστα: 3 αναθέσεις «Έτοιμος · δεν άνοιξε»")
    row = gm.locator("tr[data-id]", has_text="Ελένη Δοκιμή"); row.locator("[data-copy]").click(); gm.wait_for_timeout(200)
    check(gm.evaluate("navigator.clipboard.readText()") == L["Ελένη Δοκιμή"], "«Αντιγραφή» ξανά οποτεδήποτε: ίδιος σύνδεσμος")
    no_js_errors(gm, "ΓΔ σύνδεσμοι")

    # ══ 2. Υπολογιστής καταστήματος: ο manager είναι συνδεδεμένος και ανοίγει τον σύνδεσμο ══
    store = new_page(b); login(store, "glyfada@test.gr")
    check(store.evaluate("!!localStorage.getItem('mega-payroll-auth')"), "πριν: ο manager έχει ενεργή συνεδρία στον browser")
    emp = store.context.new_page(); emp.set_default_timeout(10000); errs = []
    emp.on("pageerror", lambda e: errs.append(str(e)))
    emp.goto(L["Ελένη Δοκιμή"]); emp.wait_for_selector("#lk-go")
    t = emp.inner_text("body")
    check("Ελένη Δοκιμή" in t and "Αξιολόγηση Νοεμβρίου (e2e)" in t and "T100" not in t, "ο σύνδεσμος ανοίγει τη σωστή αξιολόγηση της σωστής εργαζόμενης")
    check(emp.evaluate("location.hash") == "" and "a.html" in emp.url, "το κλειδί αφαιρείται από τη γραμμή διεύθυνσης")
    check(emp.evaluate("document.querySelectorAll('a[href]').length") == 0 and emp.locator("#nav, #app, .sidebar").count() == 0, "σελίδα χωρίς μενού ή συνδέσμους προς τη διαχείριση")
    check(not emp.evaluate("!!localStorage.getItem('mega-payroll-auth')"), "με το άνοιγμα, ο browser αποσυνδέεται από τη διαχείριση")
    store.reload(); store.wait_for_selector("#login-email:visible")
    check(store.is_visible("#login-email") and not store.is_visible("#app"), "η διαχείριση στην ίδια οθόνη ζητά ξανά κωδικό")
    # Απομόνωση από το πρόγραμμα περιήγησης του εργαζομένου
    probe = emp.evaluate("""async () => { const c = window.MEGA_CONFIG; const H = { apikey: c.supabaseAnonKey, Authorization: 'Bearer ' + c.supabaseAnonKey, 'Content-Type': 'application/json' };
      const r1 = await fetch(c.supabaseUrl + '/rest/v1/employees?select=*', { headers: H });
      const r2 = await fetch(c.supabaseUrl + '/rest/v1/rpc/assessment_links', { method: 'POST', headers: H, body: JSON.stringify({ p_qid: '%s' }) });
      const r3 = await fetch(c.supabaseUrl + '/rest/v1/assessment_attempts?select=*', { headers: H });
      const r4 = await fetch(c.supabaseUrl + '/rest/v1/declarations?select=*', { headers: H });
      return [r1.status, r2.status, r3.status, r4.status]; }""" % Q)
    check(all(s >= 400 for s in probe), f"από τη σελίδα: καμία πρόσβαση σε εργαζόμενους, συνδέσμους, αποτελέσματα, μισθοδοσία ({probe})")
    payload = emp.evaluate("""async (k) => { const c = window.MEGA_CONFIG; const r = await fetch(c.supabaseUrl + '/rest/v1/rpc/link_get', { method: 'POST', headers: { apikey: c.supabaseAnonKey, Authorization: 'Bearer ' + c.supabaseAnonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_token: k }) }); return await r.text(); }""", L["Ελένη Δοκιμή"].split("#")[1])
    check(not re.search(r'"(correct|points|score|is_correct|max_score)"', payload), "τα δεδομένα της σελίδας δεν περιέχουν σωστές απαντήσεις ή βαθμούς")

    # ══ 3. Συμπλήρωση, προσωρινή αποθήκευση, ανανέωση σελίδας, διακοπή σύνδεσης ══
    emp.click("#lk-go"); emp.wait_for_selector(".fq")
    check(emp.locator(".fq").count() == 3, "μόνο οι ερωτήσεις της ειδικότητάς της (3)")
    emp.locator(".fq", has_text="Τι σημαίνει DR").locator("text=Δοκιμαστικό").click()
    emp.wait_for_function("document.querySelector('#lk-saved').textContent.includes('αποθηκεύτηκε')", timeout=6000)
    emp.reload(); emp.wait_for_selector("#lk-go")
    check(emp.inner_text("#lk-go") == "Συνέχεια", "μετά από ανανέωση: «Συνέχεια»")
    emp.click("#lk-go"); emp.wait_for_selector(".fq")
    check(emp.locator(".fq", has_text="Τι σημαίνει DR").locator("input[value=Β]").is_checked(), "μετά από ανανέωση: οι απαντήσεις είναι εκεί")
    emp.context.set_offline(True)
    emp.locator(".fq", has_text="Τι σημαίνει DR").locator("text=Άμεση εγγραφή").click()
    emp.locator(".fq", has_text="Πόσο άνετα").locator("label.sc", has_text="4").click()
    emp.wait_for_function("document.querySelector('#lk-saved').textContent.includes('χωρίς σύνδεση')", timeout=6000)
    shot(emp, "42_link_offline")
    check("χωρίς σύνδεση" in emp.inner_text("#lk-saved"), "διακοπή σύνδεσης: ενημερώνει ότι οι απαντήσεις κρατούνται")
    emp.context.set_offline(False); emp.evaluate("window.dispatchEvent(new Event('online'))")
    emp.wait_for_function("document.querySelector('#lk-saved').textContent.includes('αποθηκεύτηκε')", timeout=8000)
    saved = sql("select a.answers::text from assessment_attempts a join assessment_assignments g on g.id = a.assignment_id where g.employee_code = 'T100'")[-1]
    check('"Α"' in saved and "4" in saved, "επαναφορά σύνδεσης: οι απαντήσεις αποθηκεύτηκαν στον server")
    check(sql("select a.status from assessment_attempts a join assessment_assignments g on g.id = a.assignment_id where g.employee_code = 'T100'")[-1] == "in_progress", "η προσωρινή αποθήκευση δεν είναι οριστική υποβολή")

    # ══ 4. Οριστική υποβολή: μία φορά ══
    emp.locator(".fq", has_text="Πόσο άνετα").locator("label.sc", has_text="4").click()  # (ήδη επιλεγμένο)
    emp.click("#lk-submit"); emp.wait_for_selector("#lk-yes:visible")
    shot(emp, "43_link_confirm")
    emp.dblclick("#lk-yes")
    emp.wait_for_selector("text=Η αξιολόγησή σας υποβλήθηκε επιτυχώς")
    t = emp.inner_text("body")
    check(not re.search(r"\d+\s*/\s*\d+|βαθμ|σωστ", t), "μετά την υποβολή: χωρίς βαθμολογία ή σωστές απαντήσεις")
    shot(emp, "44_link_done")
    check(sql("select count(*) from assessment_attempts a join assessment_assignments g on g.id = a.assignment_id where g.employee_code = 'T100' and a.status <> 'in_progress'")[-1] == "1", "διπλό πάτημα: μία μόνο υποβολή")
    emp.goto(L["Ελένη Δοκιμή"]); emp.wait_for_selector("text=Η αξιολόγησή σας υποβλήθηκε επιτυχώς")
    check(emp.locator(".fq, textarea, input").count() == 0, "ξανά άνοιγμα του συνδέσμου: ούτε φόρμα ούτε απαντήσεις")
    check(not errs, f"σελίδα συνδέσμου: χωρίς σφάλματα JavaScript {errs}")

    # ══ 5. Ταυτόχρονο άνοιγμα σε δύο καρτέλες ══
    t1 = store.context.new_page(); t2 = store.context.new_page()
    for tp in (t1, t2):
        tp.goto(L["Κώστας Παράδειγμα"]); tp.wait_for_selector("#lk-go"); tp.click("#lk-go"); tp.wait_for_selector(".fq")
        tp.locator(".fq", has_text="Τι σημαίνει DR").locator("text=Χαμένη ενημέρωση").click()
        tp.locator(".fq", has_text="Πόσο άνετα").locator("label.sc", has_text="2").click()
        tp.click("#lk-submit"); tp.wait_for_selector("#lk-yes:visible")
    t1.evaluate("document.querySelector('#lk-yes').click()"); t2.evaluate("document.querySelector('#lk-yes').click()")
    for tp in (t1, t2): tp.wait_for_selector("text=Η αξιολόγησή σας υποβλήθηκε επιτυχώς")
    check(sql("select count(*) || '|' || min(score) from assessment_attempts a join assessment_assignments g on g.id = a.assignment_id where g.employee_code = 'T200' and a.status <> 'in_progress'")[-1] == "1|0.00", "δύο καρτέλες ταυτόχρονα: μία μόνο υποβολή")
    t1.close(); t2.close()

    # ══ 6. Χρονικά όρια (ώρα server) ══
    A101 = sql("select id from assessment_assignments where employee_code = 'T101'")[-1]
    sql(f"select link_set_window(array['{A101}']::uuid[], '{ath(120)}', '{ath(240)}', 'αργότερα')", OWNER)
    emp.goto(L["Σάκης Τεστάκης"]); emp.wait_for_selector("h1")
    check("δεν είναι ακόμη διαθέσιμη" in emp.inner_text("h1") and emp.locator(".fq").count() == 0, "πριν από την έναρξη: «δεν είναι ακόμη διαθέσιμη», χωρίς ερωτήσεις")
    shot(emp, "45_link_scheduled")
    sql(f"select link_set_window(array['{A101}']::uuid[], '{ath(-60)}', '{ath(60)}', 'τώρα')", OWNER)
    emp.click("#lk-retry"); emp.wait_for_selector("#lk-go"); emp.click("#lk-go"); emp.wait_for_selector(".fq")
    emp.locator(".fq", has_text="Ελέγχετε τα όργανα").locator("text=Ναι").click()
    emp.wait_for_function("document.querySelector('#lk-saved').textContent.includes('αποθηκεύτηκε')", timeout=6000)
    sql(f"select link_set_window(array['{A101}']::uuid[], '{ath(-60)}', '{ath(-1)}', 'λήξη ενώ είναι ανοιχτή')", OWNER)
    emp.click("#lk-submit"); emp.click("#lk-yes"); emp.wait_for_selector("text=Η προθεσμία έληξε")
    check(sql(f"select status from assessment_attempts where assignment_id = '{A101}'")[-1] == "in_progress", "μετά τη λήξη: η υποβολή απορρίπτεται, ακόμη κι αν η σελίδα ήταν ανοιχτή")
    shot(emp, "46_link_expired")

    # ══ 7. ΓΔ: ακύρωση, επανέκδοση, παράταση με ιστορικό ══
    fresh(gm, f"#/assessment?id={Q}&tab=links")
    srow = gm.locator("tr[data-id]", has_text="Σάκης Τεστάκης")
    check("Έληξε χωρίς υποβολή" in srow.inner_text(), "ΓΔ: «Έληξε χωρίς υποβολή»")
    srow.locator("[data-cancel]").click(); gm.fill("#cb-input", "δοκιμή ακύρωσης"); gm.click("#cb-ok"); gm.wait_for_timeout(700)
    emp.goto(L["Σάκης Τεστάκης"]); emp.wait_for_selector("h1")
    check("δεν είναι διαθέσιμος" in emp.inner_text("h1"), "ακυρωμένος σύνδεσμος: δεν ανοίγει")
    srow = gm.locator("tr[data-id]", has_text="Σάκης Τεστάκης")
    check("Ακυρώθηκε" in srow.inner_text(), "ΓΔ: «Ακυρώθηκε»")
    srow.locator("[data-re]").click(); gm.click("#cb-ok"); gm.wait_for_timeout(800)
    new_url = gm.evaluate("navigator.clipboard.readText()")
    check("/a.html#" in new_url and new_url != L["Σάκης Τεστάκης"], "επανέκδοση: νέος σύνδεσμος, αντιγράφεται αυτόματα")
    srow = gm.locator("tr[data-id]", has_text="Σάκης Τεστάκης"); srow.locator("[data-win]").click()
    gm.fill("#lw-e", dl(120)); gm.fill("#lw-n", "παράταση 2 ωρών"); gm.click("#lw-ok"); gm.wait_for_timeout(700)
    check("Σε εξέλιξη" in gm.locator("tr[data-id]", has_text="Σάκης Τεστάκης").inner_text(), "παράταση: ξανά «Σε εξέλιξη»")
    gm.locator("tr[data-id]", has_text="Σάκης Τεστάκης").locator("[data-hist]").click(); gm.wait_for_selector("#dlg .list-item")
    ht = gm.inner_text("#dlg")
    check(all(x in ht for x in ("Δημιουργία", "Πρώτο άνοιγμα", "Αλλαγή διαθεσιμότητας", "Ακύρωση συνδέσμου", "Επανέκδοση συνδέσμου", "παράταση 2 ωρών", "δοκιμή ακύρωσης")), "ιστορικό: δημιουργία, άνοιγμα, αλλαγές διαθεσιμότητας, ακύρωση, επανέκδοση")
    shot(gm, "47_links_history"); gm.click("#dlg [data-close]")
    emp.goto(L["Σάκης Τεστάκης"]); emp.wait_for_selector("h1")
    check("δεν είναι διαθέσιμος" in emp.inner_text("h1"), "μετά την επανέκδοση ο παλιός σύνδεσμος παραμένει άκυρος")
    emp.goto(new_url); emp.wait_for_selector("#lk-go"); emp.click("#lk-go"); emp.wait_for_selector(".fq")
    check(emp.locator(".fq", has_text="Ελέγχετε τα όργανα").locator("input[value=Α]").is_checked(), "νέος σύνδεσμος: οι προσωρινές απαντήσεις δεν χάθηκαν")
    emp.click("#lk-submit"); emp.click("#lk-yes"); emp.wait_for_selector("text=Η αξιολόγησή σας υποβλήθηκε επιτυχώς")
    fresh(gm, f"#/assessment?id={Q}&tab=links"); shot(gm, "48_links_list")
    check(gm.locator("tr[data-id]", has_text="Ελένη Δοκιμή").locator("[data-re]").count() == 0, "ολοκληρωμένη: χωρίς επανέκδοση (μόνο νέα ανάθεση)")

    # ══ 8. Αποτελέσματα στην ενιαία καρτέλα εργαζομένου ══
    go(gm, "#/employee?code=T100&tab=assess")
    ct = gm.inner_text("#view")
    check("Αξιολόγηση Νοεμβρίου (e2e)" in ct and "Προσωπικός σύνδεσμος" in ct and "2 / 2" in ct, "καρτέλα T100 (ΓΔ): αποτέλεσμα 2/2 από προσωπικό σύνδεσμο")
    shot(gm, "49_card_result")
    mg = new_page(b); login(mg, "glyfada@test.gr"); go(mg, "#/employee?code=T100&tab=assess")
    mt = mg.inner_text("#view")
    check("Υποβλήθηκε" in mt and "2 / 2" not in mt, "καρτέλα T100 (manager): κατάσταση χωρίς βαθμούς")
    go(mg, f"#/assessment?id={Q}&tab=links")
    check("Προσωπικοί σύνδεσμοι" not in mg.inner_text("#view"), "manager: καμία πρόσβαση στη διαχείριση συνδέσμων")
    go(mg, "#/assess-run")
    check("Έναρξη συμπλήρωσης" in mg.inner_text("#view"), "η υπάρχουσα «Έναρξη συμπλήρωσης» λειτουργεί όπως πριν")
    no_js_errors(mg, "manager"); no_js_errors(gm, "ΓΔ")

print(f"\n{len(RESULTS)} έλεγχοι πέρασαν")
