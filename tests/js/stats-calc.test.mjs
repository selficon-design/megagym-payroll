// Έλεγχος τύπων στατιστικών (node --test)
import test from "node:test";
import assert from "node:assert/strict";
import { totals, metrics, fmtPct, warnings, parseCount, daysBetween, bucketOf } from "../../web/js/stats-calc.js";

const R = (o) => ({ kind: "reception", dr: 0, lost: 0, cb: 0, trials_sent: 0, enr_fitness: 0, enr_body: 0, enr_muscle: 0, enr_from_trials: 0, ...o });

test("Ενημερώσεις = DR + LOST, εγγραφές = DR + CB", () => {
  const t = totals([R({ dr: 4, lost: 6, cb: 2, enr_fitness: 3, enr_body: 2, enr_muscle: 1 })], "reception");
  assert.equal(t.informed, 10); assert.equal(t.total_enr, 6);
});
test("διάστημα: ποσοστό από αθροίσματα, ΟΧΙ μέσος όρος ημερήσιων", () => {
  const rows = [R({ dr: 4, lost: 6, cb: 2 }), R({ dr: 1, lost: 89 })];
  const m = metrics(totals(rows, "reception"), "reception");
  assert.equal(Math.round(m.conv * 10) / 10, 7);           // (5+2)/100
  const avgOfDaily = (60 + 100 / 90) / 2;                  // 30,6% — λάθος τρόπος
  assert.notEqual(Math.round(m.conv), Math.round(avgOfDaily));
});
test("Exclusive/Fitness/BODY/MUSCLE ως προς Ενημερώσεις", () => {
  const m = metrics(totals([R({ dr: 3, lost: 7, cb: 1, enr_fitness: 2, enr_body: 1, enr_muscle: 1 })], "reception"), "reception");
  assert.equal(m.excl, 20); assert.equal(m.fit, 20); assert.equal(m.body, 10); assert.equal(m.muscle, 10);
});
test("μηδενικός παρονομαστής → «—», όχι 0%", () => {
  const m = metrics(totals([R({})], "reception"), "reception");
  assert.equal(m.conv, null); assert.equal(fmtPct(m.conv), "—");
  assert.equal(fmtPct(metrics(totals([], "exclusive"), "exclusive").trialconv), "—");
});
test("CB από προηγούμενες ημέρες: χωρίς περιορισμό στο 100%", () => {
  const m = metrics(totals([R({ dr: 1, lost: 1, cb: 5, enr_fitness: 6 })], "reception"), "reception");
  assert.equal(m.conv, 300);
});
test("Επίβλεψη: δοκιμαστικά ξεχωριστά από DR/CB, Pilates ξεχωριστά", () => {
  const t = totals([{ kind: "supervision", dr: 2, lost: 3, cb: 1, trials_sent: 4, trials_attended: 2, trials_enrolled: 1, enr_body: 1, enr_muscle: 1, enr_pilates: 1 }], "supervision");
  const m = metrics(t, "supervision");
  assert.equal(t.total_enr, 3);                             // DR + CB, όχι + δοκιμαστικά
  assert.equal(m.conv, 60); assert.equal(m.attend, 50); assert.equal(m.trialenr, 50);
  assert.equal(t.enr_pilates, 1);
});
test("προειδοποιήσεις αντί για απόρριψη", () => {
  const w = warnings(totals([{ kind: "supervision", dr: 0, lost: 0, cb: 0, trials_sent: 1, trials_attended: 3, trials_enrolled: 0, enr_body: 0, enr_muscle: 0, enr_pilates: 0 }], "supervision"), "supervision");
  assert.equal(w.length, 1);
  assert.equal(warnings(totals([R({ dr: 2, cb: 1, enr_fitness: 1 })], "reception"), "reception").length, 1);
});
test("Exclusive: μετατροπή δοκιμαστικών", () => {
  assert.equal(metrics(totals([{ kind: "exclusive", trials_done: 5, enr_from_trials: 2 }], "exclusive"), "exclusive").trialconv, 40);
});
test("μόνο μη αρνητικοί ακέραιοι", () => {
  assert.equal(parseCount("3").value, 3); assert.ok(parseCount("").empty); assert.equal(parseCount("0").value, 0);
  for (const bad of ["-1", "1.5", "1,5", "abc", "1e3"]) assert.ok(parseCount(bad).error, bad);
});
test("από–έως με συμπερίληψη και των δύο ημερομηνιών (και αλλαγή ώρας)", () => {
  assert.equal(daysBetween("2026-10-24", "2026-10-26").length, 3);
  assert.deepEqual(daysBetween("2026-10-25", "2026-10-25"), ["2026-10-25"]);
  assert.equal(bucketOf("2026-10-29", 100), "2026-10-26");
});
