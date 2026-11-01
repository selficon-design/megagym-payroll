// Ημερήσια στατιστικά: πεδία ανά ειδικότητα και υπολογισμοί.
// ΚΑΝΟΝΑΣ: τα ποσοστά ενός διαστήματος υπολογίζονται από τα ΑΘΡΟΙΣΜΑΤΑ των αρχικών μεγεθών,
// ποτέ ως μέσος όρος ημερήσιων ή ατομικών ποσοστών. Μηδενικός παρονομαστής → «—».
// Δεν υπάρχουν στόχοι, όρια επιτυχίας ή συνολική βαθμολογία.

export const FIELD_LABEL = {
  dr: "DR — άμεσες εγγραφές",
  lost: "LOST",
  cb: "CB — εγγραφές σε επιστροφή",
  trials_sent: "Δοκιμαστικά που έστειλε",
  trials_attended: "Δοκιμαστικά που προσήλθαν",
  trials_enrolled: "Δοκιμαστικά που γράφτηκαν",
  trials_done: "Δοκιμαστικά που εκτέλεσε",
  enr_fitness: "Εγγραφές Fitness / GYM",
  enr_body: "Εγγραφές MEGA BODY",
  enr_muscle: "Εγγραφές MEGA MUSCLE",
  enr_pilates: "Εγγραφές Pilates",
  enr_from_trials: "Εγγραφές από δοκιμαστικά",
};
export const FIELD_SHORT = {
  dr: "DR", lost: "LOST", cb: "CB", trials_sent: "Δοκ. έστειλε", trials_attended: "Δοκ. προσήλθαν",
  trials_enrolled: "Δοκ. γράφτηκαν", trials_done: "Δοκ. εκτέλεσε", enr_fitness: "Fitness", enr_body: "BODY",
  enr_muscle: "MUSCLE", enr_pilates: "Pilates", enr_from_trials: "Εγγρ. από δοκ.",
};

const pct = (n, d) => (d > 0 ? (n / d) * 100 : null);

export const KINDS = {
  reception: {
    label: "Ρεσεψιόν",
    fields: ["dr", "lost", "cb", "trials_sent", "enr_fitness", "enr_body", "enr_muscle", "enr_from_trials"],
    metrics: [
      { key: "conv", label: "Συνολική μετατροπή", formula: "(DR + CB) ÷ Ενημερώσεις", f: (t) => pct(t.dr + t.cb, t.informed) },
      { key: "excl", label: "Exclusive", formula: "(BODY + MUSCLE) ÷ Ενημερώσεις", f: (t) => pct(t.enr_body + t.enr_muscle, t.informed) },
      { key: "fit", label: "Fitness", formula: "FITNESS ÷ Ενημερώσεις", f: (t) => pct(t.enr_fitness, t.informed) },
      { key: "body", label: "BODY", formula: "BODY ÷ Ενημερώσεις", f: (t) => pct(t.enr_body, t.informed) },
      { key: "muscle", label: "MUSCLE", formula: "MUSCLE ÷ Ενημερώσεις", f: (t) => pct(t.enr_muscle, t.informed) },
    ],
  },
  supervision: {
    label: "Επίβλεψη",
    fields: ["dr", "lost", "cb", "trials_sent", "trials_attended", "trials_enrolled", "enr_body", "enr_muscle", "enr_pilates"],
    metrics: [
      { key: "conv", label: "Συνολική μετατροπή", formula: "(DR + CB) ÷ Ενημερώσεις", f: (t) => pct(t.dr + t.cb, t.informed) },
      { key: "attend", label: "Προσέλευση δοκιμαστικών", formula: "Προσήλθαν ÷ Έστειλε", f: (t) => pct(t.trials_attended, t.trials_sent) },
      { key: "trialenr", label: "Εγγραφή όσων προσήλθαν", formula: "Γράφτηκαν ÷ Προσήλθαν", f: (t) => pct(t.trials_enrolled, t.trials_attended) },
    ],
  },
  exclusive: {
    label: "Exclusive",
    fields: ["trials_done", "enr_from_trials"],
    metrics: [
      { key: "trialconv", label: "Μετατροπή δοκιμαστικών", formula: "Εγγραφές από δοκιμαστικά ÷ Δοκιμαστικά που εκτέλεσε", f: (t) => pct(t.enr_from_trials, t.trials_done) },
    ],
  },
};

/** Έλεγχος τιμής πεδίου πλήθους: μόνο μη αρνητικοί ακέραιοι. "" = δεν συμπληρώθηκε. */
export function parseCount(v) {
  const s = String(v ?? "").trim();
  if (s === "") return { empty: true };
  if (!/^\d{1,6}$/.test(s)) return { error: "Μόνο μη αρνητικοί ακέραιοι" };
  return { value: Number(s) };
}

/** Αθροίσματα αρχικών μεγεθών + παράγωγα (ενημερώσεις, συνολικές εγγραφές). */
export function totals(rows, kind) {
  const t = { days: 0 };
  for (const f of KINDS[kind].fields) t[f] = 0;
  for (const r of rows) {
    if (r.kind !== kind) continue;
    t.days++;
    for (const f of KINDS[kind].fields) t[f] += Number(r[f] || 0);
  }
  if (kind !== "exclusive") {
    t.informed = t.dr + t.lost;          // Ενημερώσεις = DR + LOST
    t.total_enr = t.dr + t.cb;           // Συνολικές εγγραφές = DR + CB (τα προγράμματα ΔΕΝ προστίθενται ξανά)
  }
  return t;
}

export function metrics(t, kind) {
  return Object.fromEntries(KINDS[kind].metrics.map((m) => [m.key, m.f(t)]));
}

export function fmtPct(v) {
  if (v === null || v === undefined || !isFinite(v)) return "—";
  return v.toLocaleString("el-GR", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + "%";
}

/** Προειδοποιήσεις προς έλεγχο — ποτέ αυτόματη απόρριψη. */
export function warnings(t, kind) {
  const w = [];
  if (kind === "reception") {
    const prog = t.enr_fitness + t.enr_body + t.enr_muscle;
    if (prog !== t.dr + t.cb) w.push(`Η ανάλυση ανά πρόγραμμα (${prog}) δεν συμφωνεί με τις συνολικές εγγραφές DR + CB (${t.dr + t.cb}).`);
  }
  if (kind === "supervision") {
    const prog = t.enr_body + t.enr_muscle + t.enr_pilates;
    if (prog > t.dr + t.cb) w.push(`Οι εγγραφές BODY/MUSCLE/Pilates (${prog}) ξεπερνούν τις συνολικές εγγραφές DR + CB (${t.dr + t.cb}).`);
    if (t.trials_attended > t.trials_sent) w.push(`Προσήλθαν (${t.trials_attended}) περισσότερα δοκιμαστικά από όσα στάλθηκαν (${t.trials_sent}) — μπορεί να αφορούν άλλες ημέρες· ελέγξτε.`);
    if (t.trials_enrolled > t.trials_attended) w.push(`Γράφτηκαν (${t.trials_enrolled}) περισσότεροι από όσους προσήλθαν (${t.trials_attended}) — μπορεί να αφορούν άλλες ημέρες· ελέγξτε.`);
  }
  if (kind === "exclusive" && t.enr_from_trials > t.trials_done) {
    w.push(`Εγγραφές από δοκιμαστικά (${t.enr_from_trials}) περισσότερες από τα δοκιμαστικά (${t.trials_done}) — μπορεί να αφορούν άλλες ημέρες· ελέγξτε.`);
  }
  return w;
}

/** Ομαδοποίηση σε Map(κλειδί → γραμμές). */
export function groupBy(rows, keyFn) {
  const m = new Map();
  for (const r of rows) { const k = keyFn(r); if (!m.has(k)) m.set(k, []); m.get(k).push(r); }
  return m;
}

/** Ημερομηνίες (YYYY-MM-DD) από–έως, συμπεριλαμβανομένων και των δύο. */
export function daysBetween(from, to) {
  const out = [];
  const d = new Date(from + "T12:00:00Z"), end = new Date(to + "T12:00:00Z");
  while (d <= end && out.length < 1200) { out.push(d.toISOString().slice(0, 10)); d.setUTCDate(d.getUTCDate() + 1); }
  return out;
}

/** Κλειδί περιόδου για το διάγραμμα εξέλιξης: ημέρα (έως 45 ημέρες), εβδομάδα (έως ~7 μήνες), αλλιώς μήνας. */
export function bucketOf(dateIso, nDays) {
  if (nDays <= 45) return dateIso;
  if (nDays <= 210) {
    const d = new Date(dateIso + "T12:00:00Z");
    const dow = (d.getUTCDay() + 6) % 7; // Δευτέρα = 0
    d.setUTCDate(d.getUTCDate() - dow);
    return d.toISOString().slice(0, 10);
  }
  return dateIso.slice(0, 7);
}
