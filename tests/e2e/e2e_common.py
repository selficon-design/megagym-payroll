import re, json, time
from playwright.sync_api import sync_playwright, expect
BASE = "http://localhost:8787/"
SHOTS = __import__("os").path.dirname(__file__) + "/shots/"
RESULTS = []
def ok(label): RESULTS.append(("OK", label)); print("  OK", label, flush=True)
def check(cond, label):
    if not cond: raise AssertionError("ΑΠΟΤΥΧΙΑ: " + label)
    ok(label)
def browser(p):
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox"])
    return b
def new_page(b, w=1360, hgt=900):
    ctx = b.new_context(viewport={"width": w, "height": hgt}, locale="el-GR", timezone_id="Europe/Athens")
    pg = ctx.new_page(); pg.set_default_timeout(10000)
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.on("console", lambda m: errs.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)
    pg._errs = errs
    return pg
def login(pg, email):
    pg.goto(BASE); pg.wait_for_selector("#login-email:visible, #app:visible")
    if pg.is_visible("#app"):
        pg.evaluate("localStorage.clear(); sessionStorage.clear()"); pg.goto(BASE); pg.wait_for_selector("#login-email:visible")
    pg.fill("#login-email", email); pg.fill("#login-password", "test1234"); pg.click("#login-form button")
    pg.wait_for_selector("#app:visible"); pg.wait_for_selector("#view .page-head, #view .card")
def go(pg, hash):
    pg.evaluate(f"location.hash = {json.dumps(hash)}"); pg.wait_for_timeout(250); pg.wait_for_selector("#view .page-head, #view .card"); pg.wait_for_load_state("networkidle")
def confirm_dialog(pg):
    pg.wait_for_selector("#cb-ok:visible"); pg.click("#cb-ok")
def shot(pg, name): pg.screenshot(path=SHOTS + name + ".png", full_page=True)
def no_js_errors(pg, label):
    e = [x for x in pg._errs if "net::" not in x]
    check(not e, f"{label}: χωρίς σφάλματα JavaScript" + (f" {e}" if e else ""))
