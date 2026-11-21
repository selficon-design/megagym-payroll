# 3.1 σε πραγματικό Chrome (καθαρή βάση): Αναρρωτική Άδεια ως κατηγορία, αλλαγή ημερομηνιών εκκρεμούς άδειας και
# μερική έγκριση, 12 επιλογές, Ρεπό / διαγραφή ωραρίου, ώρες μετά τις 22:00 (λογιστήριο), ειδοποιήσεις αλλαγών,
# αυτόματος κωδικός, «Οι εργασίες μου», αναφορές καταστημάτων, σύνδεσμος στατιστικών, παλιά μέλη, βελτίωση & συνεργασία.
# Μόνο εικονικά στοιχεία (βάση mg_e2e), καμία πραγματική ειδοποίηση.
from e2e_common import *
import subprocess, datetime, os

def sql(q):
    p = subprocess.run(["psql", "-h", "localhost", "-U", "postgres", "-d", "mg_e2e", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"], input=q + ";\n", capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return [l for l in p.stdout.splitlines() if l.strip()]

today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=2))).date()
mon = today + datetime.timedelta(days=7 - today.weekday())          # επόμενη Δευτέρα
d = lambda x: (mon + datetime.timedelta(days=x)).isoformat()
sql("select set_config('request.jwt.claims','{\"email\":\"hr@test.gr\"}', false); set role authenticated; select leave_set_base('T100', 22, '2024-03-01', 'Βάση')")

with sync_playwright() as p:
    b = browser(p)

    # ══ 1. Manager: Αναρρωτική Άδεια ως κατηγορία, αίτημα άδειας και αλλαγή ημερομηνιών πριν από την έγκριση ══
    m = new_page(b); login(m, "glyfada@test.gr"); go(m, "#/request-new?kind=employee")
    opts = m.eval_on_selector_all("#rf-cat option", "o => o.map(x => x.textContent)")
    check(opts[:9] == ["Άδεια / απουσία", "Αναρρωτική Άδεια", "Αλλαγή βάρδιας, ρεπό ή προγράμματος", "Αύξηση αποδοχών", "Αλλαγή ωρών ή σύμβασης", "Προκαταβολή", "Βεβαιώσεις και έγγραφα", "Μετακίνηση καταστήματος ή αλλαγή θέσης", "Λοιπό αίτημα προς HR"],
          "κατηγορίες με την ακριβή σειρά της 3.1")
    m.select_option("#rf-emp", "T100"); m.click("[data-mode=manager_record]")
    check("sick" not in m.eval_on_selector_all("#rf-lt option", "o => o.map(x => x.value)"), "η αναρρωτική δεν είναι πια είδος της «Άδεια / απουσία»")
    m.select_option("#rf-lt", "annual"); m.fill("#rf-days", "5"); m.fill("#rf-start", d(0)); m.fill("#rf-end", d(4)); m.dispatch_event("#rf-end", "input")
    m.wait_for_timeout(500); m.click("#rf-submit"); confirm_dialog(m) if m.is_visible("#cb-ok") else None
    m.wait_for_selector("[data-act=redate]")
    m.click("[data-act=redate]"); m.wait_for_selector("#rd-s")
    m.fill("#rd-s", d(1)); m.fill("#rd-e", d(3)); m.fill("#rd-d", "3"); m.fill("#rd-r", "Ο εργαζόμενος μετέθεσε την έναρξη")
    m.click("#rd-ok"); m.wait_for_selector("text=Αναθεωρήσεις ημερομηνιών")
    t = m.inner_text("#view")
    check("τρέχουσα" in t and "Αρχική υποβολή" in t, "αλλαγή ημερομηνιών: κρατιούνται αρχικές ημερομηνίες και αναθεωρήσεις")
    req = m.evaluate("location.hash").split("id=")[1].split("&")[0]
    no_js_errors(m, "manager αίτημα"); m.context.close()

    # ══ 2. HR: μερική έγκριση με επιλογή ημερών ══
    h = new_page(b); login(h, "hr@test.gr"); go(h, f"#/request?id={req}")
    h.click("[data-act=decide]"); h.wait_for_selector("#dd-mode")
    h.click("#dd-mode [data-m=some]"); h.wait_for_selector(".dd-inc")
    h.uncheck(f'.dd-inc[data-day="{d(3)}"]'); h.wait_for_timeout(300)
    check("Δεν εγκρίνονται" in h.inner_text("#dd-cmp") and h.is_visible("#dd-diffbox"), "μερική έγκριση: σύγκριση και πεδίο αιτιολογίας")
    h.fill("#dd-diff", "Δεν καλύπτεται το πρόγραμμα της τελευταίας ημέρας"); h.click("#dd-ok"); h.wait_for_timeout(900)
    check("δεν εγκρίθηκαν" in h.inner_text("#view"), "η απόφαση δείχνει τις ημέρες που δεν εγκρίθηκαν")
    check(sql(f"select count(*) from leave_days where request_id = '{req}' and status = 'active'")[-1] == "2", "μόνο οι εγκεκριμένες ημέρες καταχωρίστηκαν")
    no_js_errors(h, "HR μερική έγκριση"); h.context.close()

    # ══ 3. Manager: Ρεπό, διαγραφή ωραρίου, μετά την οριστικοποίηση → ειδοποίηση λογιστηρίου ══
    m = new_page(b); login(m, "glyfada@test.gr")
    sql(f"select set_config('request.jwt.claims','{{\"email\":\"glyfada@test.gr\"}}', false); set role authenticated; select sched_set_pattern('T100', '{d(-7)}', '{{\"1\":[[\"17:00\",\"23:30\"]],\"2\":[[\"17:00\",\"01:30\"]],\"3\":[[\"08:00\",\"16:00\"]]}}', null)")
    go(m, f"#/schedule?week={d(8)}")
    m.click('[data-emp="T100"]'); m.wait_for_selector("#ed-t")
    m.check(f'.td[value="{d(9)}"]'); m.uncheck(f'.td[value="{d(8)}"]') if m.is_checked(f'.td[value="{d(8)}"]') else None
    m.select_option("#ed-t .tpl", "OFF"); check(m.is_visible("#ed-t .off-tag"), "επιλογή «Ρεπό»: εμφανίζεται «Ρεπό», όχι «Έτοιμο ωράριο»")
    m.click("#ed-ok"); m.wait_for_timeout(800)
    go(m, f"#/schedule?week={d(9)}")
    check("Ρεπό" in m.inner_text(".sc-grid"), "το πρόγραμμα γράφει «Ρεπό»")
    go(m, f"#/schedule?week={d(0)}")
    m.click("#sc-final"); m.wait_for_timeout(700)
    m.click('[data-emp="T100"]'); m.wait_for_selector("#ed-del")
    for x in m.query_selector_all(".td:checked"): x.uncheck()
    m.check(f'.td[value="{d(0)}"]'); m.click("#ed-del"); m.wait_for_timeout(500)
    check("αιτιολογία" in m.inner_text("#ed-m"), "διαγραφή σε οριστικοποιημένο: απαιτείται αιτιολογία")
    m.fill("#ed-reason", "Αλλαγή διαθεσιμότητας"); m.click("#ed-del"); m.wait_for_timeout(900)
    go(m, f"#/schedule?week={d(0)}")
    check("Διαγράφηκε το ωράριο" in m.inner_text(".sc-grid"), "η διαγραφή φαίνεται στο πρόγραμμα")
    check("(+1)" in m.inner_text("#view"), "βάρδια μετά τα μεσάνυχτα με ένδειξη (+1)")
    check(m.query_selector("#sc-night") is None, "ο manager δεν βλέπει τις ώρες μετά τις 22:00 (προβολή λογιστηρίου)")
    no_js_errors(m, "manager πρόγραμμα"); m.context.close()

    a = new_page(b); login(a, "accounting@test.gr")
    check("Αλλαγές προγράμματος" in a.inner_text("#nav") and a.query_selector('#nav a[data-id="schedule-alerts"] .count'), "λογιστήριο: «Αλλαγές προγράμματος» με αριθμό αδιάβαστων")
    go(a, "#/schedule-alerts")
    t = a.inner_text("#view")
    check("Γλυφάδα" in t and "Διαγραφή ωραρίου" in t and "Αλλαγή διαθεσιμότητας" in t and "glyfada@test.gr" in t, "ειδοποίηση: κατάστημα, αλλαγή, αιτιολογία, χρήστης")
    a.click("#sa-readall"); a.wait_for_timeout(700)
    check(a.query_selector('#nav a[data-id="schedule-alerts"] .count') is None, "ανάγνωση: ο αριθμός μηδενίζεται")
    go(a, "#/schedule")
    check("Ώρες μετά τις 22:00" in a.inner_text("#view") and a.query_selector(".sc-grid") is None, "λογιστήριο: μόνο οι ώρες μετά τις 22:00, όχι το υπόλοιπο πρόγραμμα")
    a.select_option("#sc-store", "Γλυφάδα"); a.wait_for_timeout(800); a.wait_for_load_state("networkidle"); a.wait_for_selector("#nt-f")
    a.fill("#nt-f", d(7)); a.dispatch_event("#nt-f", "change"); a.fill("#nt-t", d(13)); a.dispatch_event("#nt-t", "change"); a.wait_for_timeout(900)
    a.wait_for_function("document.querySelector('#sc-night').innerText.includes('3:30')", timeout=8000)
    check("1:30" in a.inner_text("#sc-night") and "3:30" in a.inner_text("#sc-night"), "17:00–23:30 → 1:30 και 17:00–01:30 → 3:30")
    no_js_errors(a, "λογιστήριο"); a.context.close()

    # ══ 4. Αυτόματος κωδικός & 12 επιλογές (ΓΔ) ══
    g = new_page(b); login(g, "owner@test.gr"); go(g, "#/employees")
    g.click("#em-new") if g.query_selector("#em-new") else g.click("text=+ Νέος εργαζόμενος")
    g.wait_for_selector("#ef-code"); g.fill("#ef-first", "Άρης"); g.fill("#ef-last", "Αυτόματος"); g.select_option("#ef-ww", "5"); g.click("#ef button.primary"); g.wait_for_timeout(900)
    code = sql("select code from employees where last = 'Αυτόματος'")[-1]
    check(code and code != "AUTO", f"αυτόματος κωδικός από τον server ({code})")
    go(g, "#/assessments"); g.click("#as-new"); g.fill("#nq-t", "Δοκιμή 12 επιλογών"); g.click("#nq-ok"); g.wait_for_timeout(900)
    with g.expect_download() as dl: g.click("#qq-tpl")
    check(dl.value.suggested_filename.endswith(".xlsx"), "νέο πρότυπο Excel")
    no_js_errors(g, "ΓΔ κωδικός/πρότυπο")

    # ══ 5. Αναφορά προς κατάστημα (ΓΔ → manager) & εργασίες ══
    go(g, "#/store-reports"); g.click("#sr-new"); g.wait_for_selector("#nr-s")
    g.select_option("#nr-s", "Γλυφάδα"); g.fill("#nr-subj", "Καθαριότητα αποδυτηρίων"); g.fill("#nr-d", "Στον έλεγχο τα αποδυτήρια δεν ήταν καθαρά.")
    g.check("#nr-act"); g.fill("#nr-ra", "Πρόγραμμα καθαριότητας ανά δίωρο"); g.click("#nr-ok"); g.wait_for_selector("h1:has-text('Καθαριότητα αποδυτηρίων')"); g.wait_for_load_state("networkidle")
    check("Υποβολή" in g.inner_text("#view"), "η αναφορά υποβλήθηκε με ιστορικό")
    go(g, "#/tasks?tab=all")
    check("Όλες οι ανατεθειμένες εργασίες" in g.inner_text("#view") and "Καθαριότητα αποδυτηρίων" in g.inner_text("#view"), "ΓΔ: όλες οι ανατεθειμένες εργασίες")
    no_js_errors(g, "ΓΔ αναφορά/εργασίες")

    m = new_page(b); login(m, "glyfada@test.gr")
    check(m.query_selector('#nav a[data-id="store-reports"] .count') is not None, "ο manager βλέπει ειδοποίηση αναφοράς")
    go(m, "#/tasks")
    check("Οι εργασίες μου" in m.inner_text("#view") and "Καθαριότητα αποδυτηρίων" in m.inner_text("#view"), "«Οι εργασίες μου» φορτώνει την εργασία του manager")
    go(m, "#/store-reports"); m.click("tr[data-id]"); m.wait_for_selector("#rv-done")
    m.click("#rv-claim"); m.wait_for_timeout(600)
    m.fill("#rv-n", "Τοποθετήθηκε πρόγραμμα καθαριότητας"); m.click("#rv-done"); m.wait_for_timeout(800)
    check("Ολοκληρώθηκε" in m.inner_text("#view"), "ο manager ολοκλήρωσε με σχόλιο")
    no_js_errors(m, "manager αναφορά"); m.context.close()

    # ══ 6. Σύνδεσμος στατιστικών Ρεσεψιόν + παλιά μέλη ══
    go(g, "#/stats-entry"); g.wait_for_selector("#se-links"); g.click("#se-links"); g.click('[data-new="Γλυφάδα"]'); g.wait_for_selector("#lk-url")
    url = g.input_value("#lk-url")
    check("s.html#" in url, "δημιουργία συνδέσμου (εμφανίζεται μία φορά)")
    s = new_page(b, 420, 900); s.goto(url.replace(url.split("s.html")[0], BASE)); s.wait_for_selector("#sl-emp")
    check(s.query_selector("#nav") is None and "Γλυφάδα" in s.inner_text("body"), "απομονωμένη σελίδα: μόνο το κατάστημα του συνδέσμου")
    s.select_option("#sl-emp", "T100")
    for i in s.query_selector_all("[data-f]"): i.fill("1")
    s.click("#sl-ok"); s.wait_for_selector("text=Η καταχώριση υποβλήθηκε")
    s.click("#sl-again"); s.wait_for_selector("#sl-emp"); s.select_option("#sl-emp", "T100")
    for i in s.query_selector_all("[data-f]"): i.fill("2")
    s.click("#sl-ok"); s.wait_for_timeout(800)
    check("επικοινωνήστε με τον manager" in s.inner_text("#sl-m"), "διπλή ημερήσια εγγραφή: μήνυμα χωρίς δεδομένα")
    check(sql("select count(*) || '|' || max(old_direct) from daily_stats where employee_code = 'T100' and created_by like 'σύνδεσμος%'")[-1] == "1|1", "αποθηκεύτηκε στα στατιστικά με τα παλιά μέλη")
    no_js_errors(s, "σύνδεσμος στατιστικών"); s.context.close()
    go(g, "#/stats-report"); g.click("[data-tab=members]"); g.wait_for_timeout(800)
    g.wait_for_selector("#sr-members table"); check("Νέες εγγραφές" in g.text_content("#sr-members") and "Ανανεώσεις" in g.text_content("#sr-members") and "Χωρίς διάκριση" in g.text_content("#sr-members"), "report νέων εγγραφών και ανανεώσεων")

    # ══ 7. Βελτίωση & συνεργασία, πρότυπο σταδίου 2 ══
    go(g, "#/templates")
    check("Δεν έχει προστεθεί πρότυπο" in g.inner_text("#view"), "Πρότυπα κειμένων: θέση σταδίου 2 χωρίς πρότυπο")
    go(g, "#/improvement"); g.click("#im-new"); g.wait_for_selector("#nc-e")
    g.select_option("#nc-e", "T100"); g.select_option("#nc-s", "significant"); g.fill("#nc-t", "Καθυστέρηση προσέλευσης"); g.fill("#nc-d", today.isoformat())
    g.fill("#nc-desc", "Τρεις καθυστερήσεις μέσα στον μήνα."); g.click("#nc-ok"); g.wait_for_selector("#cv-review")
    g.click("#cv-review"); g.check('input[name=rv-o][value=noncompliant]'); g.fill("#rv-r", "Νέες καθυστερήσεις μετά τη συζήτηση"); g.click("#rv-ok"); g.wait_for_timeout(800)
    check("εισήγηση" in g.inner_text("#view").lower() or "Εισήγηση" in g.inner_text("#view"), "μη συμμόρφωση: εισήγηση επόμενου σταδίου, χωρίς αυτόματη μετάβαση")
    go(g, "#/improvement?tab=summary")
    check("Συγκεντρωτικός πίνακας" in g.inner_text("#view") and "Ελένη Δοκιμή" in g.inner_text("#view"), "συγκεντρωτικός πίνακας ΓΔ")
    no_js_errors(g, "ΓΔ βελτίωση"); g.context.close()

    print(f"\n✓ {len(RESULTS)} έλεγχοι 3.1")
