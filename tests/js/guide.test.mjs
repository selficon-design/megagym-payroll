// Ο Οδηγός χρήσης (docs/guide.md) πρέπει να συμβαδίζει με την εφαρμογή. Τρέχει πριν από κάθε deploy:
// αν προστεθεί νέα σελίδα στο μενού ή αλλάξει η έκδοση χωρίς ενημέρωση του οδηγού, η δημοσίευση σταματά.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const root = new URL("../../web/", import.meta.url);
const read = (p) => readFileSync(new URL(p, root), "utf8");
const repo = new URL("../../", import.meta.url);
const guide = readFileSync(new URL("docs/guide.md", repo), "utf8");
const appVersion = read("js/version.js").match(/APP_VERSION\s*=\s*"([^"]+)"/)[1];

test("ο οδηγός γράφει την τρέχουσα έκδοση της εφαρμογής", () => {
  const m = guide.match(/GUIDE_VERSION:\s*([\d.]+)/);
  assert.ok(m, "λείπει η γραμμή <!-- GUIDE_VERSION: … --> από το docs/guide.md");
  assert.equal(m[1], appVersion, `ο οδηγός είναι για την ${m[1]}, η εφαρμογή είναι ${appVersion} — ενημερώστε το docs/guide.md`);
});

test("κάθε σελίδα του μενού περιγράφεται στον οδηγό", () => {
  const app = read("js/app.js");
  const titles = [...app.matchAll(/\{ id: "([^"]+)", title: "([^"]+)", ico: [^}]*group: "([^"]+)"/g)].map((m) => m[2]);
  assert.ok(titles.length > 15, "δεν βρέθηκαν σελίδες μενού");
  const missing = titles.filter((t) => !guide.includes(t));
  assert.deepEqual(missing, [], `σελίδες χωρίς περιγραφή στον οδηγό: ${missing.join(", ")}`);
});

test("ο οδηγός δεν δημοσιεύεται ως ανοιχτό αρχείο· τον δίνει μόνο ο server με δικαίωμα", async () => {
  assert.throws(() => read("guide.md"), "το web/guide.md δεν πρέπει να υπάρχει (θα ήταν ανοιχτό σε όλους)");
  const sw = read("sw.js");
  assert.ok(!sw.includes('"guide.md"'));
  for (const f of ["js/views-guide.js", "js/guide-pdf.js", "js/version.js"]) assert.ok(sw.includes(`"${f}"`), `λείπει το ${f} από το sw.js`);
  const { guideModule } = await import(new URL("scripts/build-guide.mjs", repo));
  const content = readFileSync(new URL("supabase/functions/guide/content.ts", repo), "utf8");
  assert.equal(content, guideModule(guide), "το supabase/functions/guide/content.ts είναι παλιό — τρέξτε: node scripts/build-guide.mjs");
  const fn = readFileSync(new URL("supabase/functions/guide/index.ts", repo), "utf8");
  assert.match(fn, /perms\.includes\("guide\.view"\)/, "η λειτουργία guide πρέπει να ελέγχει το δικαίωμα");
  assert.match(read("js/app.js"), /id: "guide"[^}]*show: \(\) => P\("guide\.view"\)/, "το μενού πρέπει να ελέγχει το δικαίωμα");
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
