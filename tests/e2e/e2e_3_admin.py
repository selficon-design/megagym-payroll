# Γενική Διευθύντρια mariamaneta@megagym.gr: προσθήκη χρήστη, κωδικός άλλου χρήστη, αλλαγή δικού της κωδικού,
# κλείδωμα — μέσα από τις πραγματικές οθόνες και την πραγματική λειτουργία server admin-users (Deno).
from e2e_common import *
import e2e_common
def login_as(pg, email, pw="test1234"):
    pg.goto(BASE); pg.wait_for_selector("#login-email:visible, #app:visible")
    if pg.is_visible("#app"): pg.evaluate("localStorage.clear(); sessionStorage.clear()"); pg.goto(BASE); pg.wait_for_selector("#login-email:visible")
    pg.fill("#login-email", email); pg.fill("#login-password", pw); pg.click("#login-form button")
    pg.wait_for_selector("#app:visible, #login-msg:has-text('Λάθος'), #login-msg:has-text('κλειδωμένος')")
    pg.wait_for_load_state("networkidle"); return pg.is_visible("#app")
with sync_playwright() as p:
    b = browser(p)
    pg = new_page(b); check(login_as(pg, "mariamaneta@megagym.gr"), "mariamaneta@megagym.gr: είσοδος")
    check("Γενική Διευθύντρια" in pg.inner_text("#me-box"), "αναγνωρίζεται ως Γενική Διευθύντρια")
    go(pg, "#/users"); pg.wait_for_timeout(600)
    pg.wait_for_timeout(600); t = pg.inner_text("#view")
    check("διαχειρίζεται λογαριασμούς" not in t and "Τελ. είσοδος" in t, "λίστα χρηστών με κατάσταση λογαριασμών από τον server")
    # Προσθήκη χρήστη
    pg.click("#us-new"); pg.fill("#uf-name", "Νέα Δοκιμαστική HR"); pg.fill("#uf-email", "nea.hr@test.gr"); pg.select_option("#uf-role", "hr")
    pg.fill("#uf-pw", "ProtosKodikos1"); pg.click("#uf button.primary"); pg.wait_for_selector("#sc-copy", timeout=8000)
    check("nea.hr@test.gr" in pg.inner_text("#dlg") and "ProtosKodikos1" in pg.inner_text("#dlg"), "προσθήκη χρήστη: δημιουργήθηκε λογαριασμός με κωδικό")
    pg.click("#dlg [data-close] >> nth=-1"); pg.wait_for_timeout(500)
    # Νέος κωδικός σε υπάρχοντα χρήστη
    pg.click('[data-pw="hr@test.gr"]'); pg.fill("#pw-new", "NeosKodikosHR9"); pg.click("#pw-ok"); pg.wait_for_selector("#sc-copy", timeout=8000)
    check("NeosKodikosHR9" in pg.inner_text("#dlg"), "αλλαγή κωδικού άλλου χρήστη")
    pg.click("#dlg [data-close] >> nth=-1"); pg.wait_for_timeout(400)
    # Κλείδωμα / ξεκλείδωμα
    pg.click('[data-act="kifisia@test.gr"]'); confirm_dialog(pg); pg.wait_for_timeout(900)
    check("Κλειδωμένος" in pg.inner_text("#view"), "κλείδωμα χρήστη")
    # Αλλαγή δικού της κωδικού
    go(pg, "#/account"); pg.fill("#ac-p1", "MariaNeos2026"); pg.fill("#ac-p2", "MariaNeos2026"); pg.click("#ac-pw button"); pg.wait_for_timeout(700)
    check("Ο κωδικός άλλαξε" in pg.inner_text("#ac-msg"), "αλλαγή δικού της κωδικού")
    no_js_errors(pg, "ΓΔ"); pg.context.close()
    # Επαλήθευση: οι νέοι κωδικοί λειτουργούν, οι παλιοί όχι, ο κλειδωμένος δεν μπαίνει
    pg = new_page(b)
    check(login_as(pg, "nea.hr@test.gr", "ProtosKodikos1") and "HR" in pg.inner_text("#me-box"), "ο νέος χρήστης μπαίνει με ρόλο HR")
    check(not login_as(pg, "hr@test.gr", "test1234") and login_as(pg, "hr@test.gr", "NeosKodikosHR9"), "HR: ο παλιός κωδικός απορρίπτεται, ο νέος λειτουργεί")
    go(pg, "#/account"); check("Διαχείριση χρηστών" not in pg.inner_text("#nav") and "Χρήστες" not in pg.inner_text("#nav"), "HR: χωρίς διαχείριση χρηστών στο μενού")
    r = pg.evaluate("""async () => { const s = JSON.parse(localStorage.getItem('mega-payroll-auth'));
      const x = await fetch('/functions/v1/admin-users', {method:'POST', headers:{Authorization:'Bearer '+s.access_token,'Content-Type':'application/json'}, body: JSON.stringify({action:'set_password', email:'mariamaneta@megagym.gr', password:'Kleftis12345'})});
      return [x.status, (await x.json()).error]; }""")
    check(r[0] == 403 and "Γενική Διευθύντρια" in r[1], f"HR: ο server αρνείται αλλαγή κωδικού άλλου {r}")
    check(not login_as(pg, "kifisia@test.gr"), "κλειδωμένος χρήστης δεν μπαίνει")
    check(not login_as(pg, "mariamaneta@megagym.gr", "test1234") and login_as(pg, "mariamaneta@megagym.gr", "MariaNeos2026"), "ΓΔ: μπαίνει με τον νέο της κωδικό")
    pg.context.close(); b.close()
print(f"\n✓ {len(RESULTS)} έλεγχοι")
