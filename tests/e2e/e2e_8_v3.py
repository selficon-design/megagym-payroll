# v3 σε πραγματικό Chrome (μετά το e2e_1, σε καθαρή βάση): πίνακας δικαιωμάτων, ημερολόγιο αδειών, χρονοδιάγραμμα
# προγράμματος με σπαστό ωράριο και οριστικοποίηση, καρτέλα αδειών, ροή υλοποίησης, «Απαντήσεις N», Exit Interview,
# PDF μόνο για ΓΔ/λογιστήριο. Μόνο εικονικά στοιχεία (βάση mg_e2e), καμία πραγματική ειδοποίηση.
from e2e_common import *
import subprocess, datetime, os
D = os.path.dirname(os.path.abspath(__file__))

def sql(q):
    p = subprocess.run(["psql", "-h", "localhost", "-U", "postgres", "-d", "mg_e2e", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"], input=q + ";\n", capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return [l for l in p.stdout.splitlines() if l.strip()]

ids = json.load(open(D + "/ids.json"))
today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=2))).date()
next_mon = today + datetime.timedelta(days=7 - today.weekday())

with sync_playwright() as p:
    b = browser(p)

    # ══ 1. Ρόλοι & Δικαιώματα (μόνο ΓΔ) ══
    gm = new_page(b); login(gm, "owner@test.gr"); go(gm, "#/permissions")
    check(gm.query_selector("table.perm-table") is not None and all(x in gm.text_content("thead") for x in ["Γενική Διευθύντρια", "HR", "Λογιστήριο", "Manager", "Εκπαιδευτής"]), "δικαιώματα: πίνακας με τους 5 ρόλους")
    check(gm.is_disabled('[data-r=owner][data-p="permissions.manage"]') and gm.is_disabled('[data-r=hr][data-p="leave.overdraw"]') and gm.is_disabled('[data-r=manager][data-p="exit.view"]'),
          "κλειδωμένα κελιά: αλλαγή δικαιωμάτων / ειδική έγκριση υπέρβασης / Exit Interview")
    check(not gm.is_checked('[data-r=manager][data-p="payroll.pdf"]') and gm.is_checked('[data-r=accounting][data-p="payroll.pdf"]') and not gm.is_checked('[data-r=hr][data-p="payroll.sign"]'),
          "αρχικές ρυθμίσεις §17: PDF μόνο ΓΔ/λογιστήριο, HR χωρίς υπογραφή")
    gm.check('[data-r=hr][data-p="stats.export"]') if not gm.is_checked('[data-r=hr][data-p="stats.export"]') else gm.uncheck('[data-r=hr][data-p="stats.export"]')
    before = sql("select role_has_perm('hr','stats.export')")[-1]
    gm.click("#pm-save"); gm.wait_for_timeout(700)
    check(sql("select role_has_perm('hr','stats.export')")[-1] == before, "χωρίς αιτιολογία: ο server δεν αποθηκεύει")
    gm.fill("#pm-note", "Δοκιμή e2e"); gm.click("#pm-save"); gm.wait_for_timeout(1000)
    check(sql("select role_has_perm('hr','stats.export')")[-1] != before and "Δοκιμή e2e" in gm.inner_text("#view"), "αλλαγή αποθηκεύτηκε στον server, με ιστορικό και αιτιολογία")
    shot(gm, "80_permissions")
    hr = new_page(b); login(hr, "hr@test.gr")
    check("Ρόλοι & Δικαιώματα" not in hr.inner_text("#nav"), "HR: δεν βλέπει τον πίνακα δικαιωμάτων")
    go(hr, "#/permissions"); check(hr.query_selector("table.perm-table") is None, "HR: άμεσο URL δεν ανοίγει τον πίνακα")
    try: hr.evaluate("import('/js/core.js').then(m => m.S.api.permSave([{role:'hr', perm:'payroll.pdf', allowed:true}], {}, 'παράκαμψη'))"); bypass = True
    except Exception: bypass = False
    check(not bypass and sql("select role_has_perm('hr','payroll.pdf')")[-1] == "f", "HR: απευθείας κλήση από τον browser απορρίπτεται από τον server")
    hr.context.close()

    # ══ 2. Ημερολόγιο αδειών ══
    go(gm, "#/leaves"); gm.wait_for_selector(".lv-month")
    for _ in range(14):
        if "Δεκέμβριος 2026" in gm.inner_text(".toolbar"): break
        gm.click("#lc-next"); gm.wait_for_timeout(300)
    cols = gm.locator(".lv-col")
    check(cols.count() == 31 and "Ελένη Δοκιμή" in cols.nth(0).inner_text() and "Ελένη Δοκιμή" in cols.nth(2).inner_text() and "Ελένη Δοκιμή" not in cols.nth(3).inner_text(), "μήνας: συνεχόμενες στήλες ημερών, εγκεκριμένη άδεια 1–3/12")
    check(gm.locator(".lv-col >> nth=0").locator(".lv-chip.approved").count() == 1 and "✓" in gm.locator(".lv-col >> nth=0").inner_text(), "εγκεκριμένη: σήμανση ✓ (όχι μόνο χρώμα)")
    gm.click("#lc-next"); gm.wait_for_timeout(400)
    jan = gm.locator(".lv-col").nth(9)
    check(jan.locator(".lv-chip.pending").count() == 1 and "⏳" in jan.inner_text(), "σε αναμονή: ξεχωριστή σήμανση ⏳")
    gm.click("[data-mode=year]"); gm.wait_for_selector("table.lv-year")
    check(gm.locator("table.lv-year tbody tr").count() == 12, "έτος: 12 μήνες")
    shot(gm, "81_leave_calendar")
    go(gm, "#/employee?code=T100&tab=leave"); gm.wait_for_selector("#card-body table")
    t = gm.inner_text("#card-body")
    check("Εγκεκριμένες μελλοντικές\n3,00" in t and "Αναρρωτικές" in t and "Εργασιακό έτος" in t, "καρτέλα: άδειες με αναλογία, αναρρωτικές ανά εργασιακό έτος")

    # ══ 3. Πρόγραμμα (manager Γλυφάδας): σπαστό ωράριο = 8 ώρες, οριστικοποίηση, αλλαγή μόνο με αιτιολογία ══
    mg = new_page(b); login(mg, "glyfada@test.gr")
    badge = mg.locator("#nav a[data-id=answers] .count.hot")
    check(badge.count() == 1 and badge.inner_text() == "1", "«Απαντήσεις 1»: αδιάβαστη απάντηση ανά χρήστη")
    go(mg, "#/answers"); mg.click("a.list-item.unread >> nth=0"); mg.wait_for_selector(".page-head"); mg.wait_for_load_state("networkidle"); mg.wait_for_timeout(500)
    check(mg.locator("#nav a[data-id=answers] .count").count() == 0, "άνοιγμα: γίνεται διαβασμένη, ο αριθμός μηδενίζεται")

    go(mg, f"#/schedule?week={next_mon.isoformat()}"); mg.wait_for_selector(".sc-grid")
    check(mg.query_selector("#sc-store") is None and "Γλυφάδα" in mg.text_content(".page-head"), "manager: μόνο το κατάστημά του")
    mg.click("[data-emp=T100]"); mg.click("[data-m=perm]"); mg.wait_for_selector("#ed-1")
    mg.click("#ed-1 .add"); mg.click("#ed-1 .add")
    ins = mg.locator("#ed-1 input[type=time]")
    for i, v in enumerate(["08:00", "12:00", "17:00", "21:00"]): ins.nth(i).fill(v)
    mg.fill("#pf-from", next_mon.isoformat()); mg.click("#ed-ok"); mg.wait_for_selector("#dlg:not([open])", state="attached"); mg.wait_for_timeout(800)
    row = mg.locator("tr", has_text="Ελένη Δοκιμή").last
    check("8,00" in row.inner_text(), "σπαστό 08–12 + 17–21 = 8 ώρες εργασίας")
    check(mg.locator(".sc-bar", has_text="08:00–12:00").count() >= 1 and mg.locator(".sc-bar", has_text="17:00–21:00").count() >= 1, "χρονοδιάγραμμα: δύο διαστήματα στη στήλη του εργαζομένου")
    check("Παρόντες" in mg.inner_text(".sc-grid") and "Υπο-/υπερστελέχωση" in mg.inner_text("#view"), "μέτρηση παρόντων ανά μισάωρο, χωρίς ετικέτα υπο/υπερστελέχωσης χωρίς απαιτήσεις")
    mg.click("#sc-final"); mg.wait_for_timeout(900)
    check("Οριστικοποιήθηκε" in mg.text_content(".page-head"), "οριστικοποίηση από τον manager χωρίς έγκριση")
    mg.click("[data-emp=T100]"); mg.wait_for_selector("#ed-t")
    mg.click("#ed-t .add"); tins = mg.locator("#ed-t .seg-row").last.locator("input")
    mg.evaluate("document.querySelectorAll('#ed-t .seg-row').forEach((r, i, a) => i < a.length - 1 && r.remove())")
    tins.nth(0).fill("09:00"); tins.nth(1).fill("13:00"); mg.click("#ed-ok"); mg.wait_for_timeout(700)
    check("αιτιολογ" in mg.inner_text("#ed-m").lower(), "αλλαγή μετά την οριστικοποίηση χωρίς αιτιολογία: απορρίπτεται")
    mg.fill("#ed-reason", "Κάλυψη βάρδιας (δοκιμή)"); mg.click("#ed-ok"); mg.wait_for_selector("#dlg:not([open])", state="attached"); mg.wait_for_timeout(800)
    check(mg.locator(".sc-bar.temp", has_text="09:00–13:00").count() == 1, "προσωρινή αλλαγή μόνο για την ημέρα")
    mg.click("#sc-hist"); mg.wait_for_selector("#dlg[open]")
    check("Κάλυψη βάρδιας (δοκιμή)" in mg.inner_text("#dlg"), "ιστορικό: αιτιολογία αλλαγής μετά την οριστικοποίηση")
    mg.keyboard.press("Escape"); shot(mg, "82_schedule")
    check(sql("select count(*) from notifications where user_email = 'owner@test.gr'")[-1] == "0", "καμία ειδοποίηση στη ΓΔ για το πρόγραμμα")

    # ΓΔ: βλέπει πρόγραμμα και ιστορικό, χωρίς επεξεργασία
    go(gm, f"#/schedule?week={next_mon.isoformat()}")
    if gm.query_selector("#sc-store"): gm.select_option("#sc-store", "Γλυφάδα"); gm.wait_for_timeout(800)
    gm.wait_for_selector(".sc-grid")
    check("Οριστικοποιήθηκε" in gm.text_content(".page-head") and gm.query_selector("[data-emp]") is None and gm.query_selector("#sc-hist") is not None, "ΓΔ: βλέπει πρόγραμμα και ιστορικό, χωρίς επεξεργασία")

    # ══ 4. Ροή υλοποίησης (manager) ══
    go(mg, f"#/request?id={ids['leave1']}")
    mg.click("[data-act=claim]"); mg.wait_for_selector("[data-act=implement]")
    check("Ανάληψη υλοποίησης" in mg.inner_text("#view") and "glyfada@test.gr" in mg.inner_text("#view"), "«Αναλαμβάνω την υλοποίηση»: καταγράφεται ποιος/πότε")
    mg.click("[data-act=implement]"); mg.fill("#im-n", "Ενημερώθηκε το πρόγραμμα (δοκιμή)"); mg.click("#im-ok"); mg.wait_for_timeout(1000)
    check(sql(f"select status from hr_requests where id = '{ids['leave1']}'")[-1] == "completed", "«Ολοκλήρωση υλοποίησης» με σχόλιο: το αίτημα ολοκληρώθηκε")
    shot(mg, "83_implemented")

    # ══ 5. Exit Interview και PDF ══
    go(mg, "#/exit-reports"); check(mg.inner_text("#page-title") != "Exit Interview — αναφορές", "manager: δεν ανοίγει αναφορές Exit Interview")
    go(mg, "#/employee?code=T100&tab=payroll"); mg.click("[data-view] >> nth=0"); mg.wait_for_selector("#dlg[open] .dlg-head"); mg.wait_for_timeout(300)
    check(mg.query_selector("#vd-pdf") is None and mg.query_selector("#vd-showsig") is None, "manager: χωρίς PDF και χωρίς εμφάνιση υπογραφής")
    no_js_errors(mg, "manager v3"); mg.context.close()

    go(gm, "#/assessments"); gm.click("#as-new"); gm.fill("#nq-t", "Exit Interview (δοκιμή)"); gm.select_option("#nq-k", "exit_interview"); gm.click("#nq-ok"); gm.wait_for_timeout(1200)
    t = gm.inner_text("#view")
    check("χωρίς σωστές απαντήσεις και βαθμό" in t and "Κλειδιά" not in gm.inner_text(".tabs"), "Exit Interview: ξεχωριστό είδος, χωρίς βαθμολογία/κλειδιά")
    go(gm, "#/exit-reports"); check(gm.inner_text("#page-title") == "Exit Interview — αναφορές", "ΓΔ: αναφορές Exit Interview")
    go(gm, "#/employee?code=T100&tab=payroll"); gm.click("[data-view] >> nth=0"); gm.wait_for_selector("#dlg[open] .dlg-head"); gm.wait_for_timeout(300)
    check(gm.query_selector("#vd-pdf") is not None, "ΓΔ: PDF διαθέσιμο")
    no_js_errors(gm, "ΓΔ v3"); gm.context.close()

    ac = new_page(b); login(ac, "accounting@test.gr")
    nav = ac.inner_text("#nav")
    check("Δηλώσεις" in nav and "Άδειες" in nav and "Ρόλοι" not in nav and "Χρήστες" not in nav, "λογιστήριο: δηλώσεις και άδειες, χωρίς διαχείριση")
    go(ac, "#/employee?code=T100&tab=payroll"); ac.click("[data-view] >> nth=0"); ac.wait_for_selector("#dlg[open] .dlg-head"); ac.wait_for_timeout(300)
    check(ac.query_selector("#vd-pdf") is not None, "λογιστήριο: PDF διαθέσιμο")
    ac.keyboard.press("Escape")
    go(ac, "#/exit-reports"); check(ac.inner_text("#page-title") != "Exit Interview — αναφορές", "λογιστήριο: όχι Exit Interview")
    go(ac, "#/leaves?tab=settle"); check("Προς εκκαθάριση" in ac.inner_text(".tabs"), "λογιστήριο: καρτέλα «Προς εκκαθάριση»")
    no_js_errors(ac, "λογιστήριο"); ac.context.close()
    b.close()
print(f"\n✓ {len(RESULTS)} έλεγχοι v3")
