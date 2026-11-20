// Ο Οδηγός χρήσης (web/guide.md) πρέπει να συμβαδίζει με την εφαρμογή. Τρέχει πριν από κάθε deploy:
// αν προστεθεί νέα σελίδα στο μενού ή αλλάξει η έκδοση χωρίς ενημέρωση του οδηγού, η δημοσίευση σταματά.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const root = new URL("../../web/", import.meta.url);
const read = (p) => readFileSync(new URL(p, root), "utf8");
const guide = read("guide.md");
const appVersion = read("js/version.js").match(/APP_VERSION\s*=\s*"([^"]+)"/)[1];

test("ο οδηγός γράφει την τρέχουσα έκδοση της εφαρμογής", () => {
  const m = guide.match(/GUIDE_VERSION:\s*([\d.]+)/);
  assert.ok(m, "λείπει η γραμμή <!-- GUIDE_VERSION: … --> από το guide.md");
  assert.equal(m[1], appVersion, `ο οδηγός είναι για την ${m[1]}, η εφαρμογή είναι ${appVersion} — ενημερώστε το web/guide.md`);
});

test("κάθε σελίδα του μενού περιγράφεται στον οδηγό", () => {
  const app = read("js/app.js");
  const titles = [...app.matchAll(/\{ id: "([^"]+)", title: "([^"]+)", ico: [^}]*group: "([^"]+)"/g)].map((m) => m[2]);
  assert.ok(titles.length > 15, "δεν βρέθηκαν σελίδες μενού");
  const missing = titles.filter((t) => !guide.includes(t));
  assert.deepEqual(missing, [], `σελίδες χωρίς περιγραφή στον οδηγό: ${missing.join(", ")}`);
});

test("ο οδηγός και η σελίδα του αποθηκεύονται για χρήση χωρίς σύνδεση", () => {
  const sw = read("sw.js");
  for (const f of ["guide.md", "js/views-guide.js", "js/version.js"]) assert.ok(sw.includes(`"${f}"`), `λείπει το ${f} από το sw.js`);
});

test("ο μετατροπέας markdown βγάζει όλες τις ενότητες και τους πίνακες", async () => {
  globalThis.document = { querySelector: () => null, querySelectorAll: () => [] };
  const { renderMarkdown } = await import(new URL("js/views-guide.js", root));
  const { html, toc } = renderMarkdown(guide);
  assert.equal(toc.length, (guide.match(/^## /gm) || []).length);
  assert.equal((html.match(/<table>/g) || []).length, (guide.match(/^\| ?-{3}/gm) || []).length);
  assert.ok(!/<script/i.test(html));
  assert.equal((html.match(/<ol>|<ul>/g) || []).length, (html.match(/<\/ol>|<\/ul>/g) || []).length, "ανισόρροπες λίστες");
});
