// Ημερήσια στατιστικά: καταχώριση ανά ημέρα/εργαζόμενο (manager) και αναφορές διαστήματος (ΓΔ, HR)
import { S, can, role, getEmployees, visibleStores, activeStores, specialtyKind, invalidate, P } from "./core.js";
import { $, $$, h, dmy, toast, openDialog, downloadXlsx } from "./util.js";
import { athens, athensToday, demoNotice } from "./hr-common.js";
import { KINDS, FIELD_LABEL, FIELD_SHORT, oldFieldsFor, baseKind, isUnsplit, oldMemberRows, parseCount, totals, metrics, fmtPct, warnings, groupBy, daysBetween, bucketOf } from "./stats-calc.js";

const view = () => $("#view");

// ═══════════════════════ Καθημερινή καταχώριση ═══════════════════════
export async function statsEntry(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Ημερήσια στατιστικά"));
  if (!can.statsEntry()) return (view().innerHTML = `<div class="card empty">Η καταχώριση γίνεται από τον manager του καταστήματος.</div>`);
  const F = (S.filters.statsEntry ??= { date: athensToday(), store: role() === "manager" ? S.me.store : activeStores()[0] });
  const [emps, rows] = await Promise.all([getEmployees(), S.api.stats({ from: F.date, to: F.date, store: F.store })]);
  const existing = Object.fromEntries(rows.map((r) => [`${r.employee_code}|${r.specialty}`, r]));
  const people = emps.filter((e) => e.store === F.store && e.status === "Ενεργός" && specialtyKind(e.specialty));
  // Όσοι έχουν καταχώριση εκείνη την ημέρα αλλά άλλαξαν μετά ειδικότητα/κατάστημα εμφανίζονται επίσης (για διόρθωση)
  const keyed = people.map((e) => ({ e, kind: specialtyKind(e.specialty), spec: e.specialty, row: existing[`${e.code}|${e.specialty}`] }));
  for (const r of rows) if (!keyed.some((k) => k.row?.id === r.id)) keyed.push({ e: { code: r.employee_code, first: emps.find((x) => x.code === r.employee_code)?.first || r.employee_code, last: emps.find((x) => x.code === r.employee_code)?.last || "" }, kind: r.kind, spec: r.specialty, row: r, readonlyNew: true });
  const noSpec = emps.filter((e) => e.store === F.store && e.status === "Ενεργός" && !specialtyKind(e.specialty));

  const section = (kind) => {
    const list = keyed.filter((k) => k.kind === kind);
    if (!list.length) return "";
    const K = KINDS[kind];
    const OLD_FIELDS = oldFieldsFor(kind), old = true;   // «Παλιά μέλη» σε κάθε είδος στατιστικών
    return `<div class="card" style="margin-top:16px"><div class="card-head"><h3>${K.label}</h3><span class="muted small">${K.metrics.map((m) => `${m.label} = ${m.formula}`).join(" · ")}</span></div>
      <p class="muted small">Δύο χωριστές ομάδες: <strong>Νέα μέλη</strong> (εγγραφές) και <strong>Παλιά μέλη</strong> (ανανεώσεις), με τα ίδια πεδία. «Άμεσο» = «Παλιά μέλη — Άμεσο»· είναι ξεχωριστό μέγεθος (δεν περιέχεται στο DR) και προστίθεται στις ανανεώσεις. Παλιές καταχωρίσεις χωρίς διάκριση μένουν ως έχουν.</p>
      <div class="table-wrap"><table class="entry"><thead>${old ? `<tr><th></th><th class="grp" colspan="${K.fields.length + 1}">Νέα μέλη</th><th class="grp" colspan="${K.metrics.length}"></th><th class="grp old" colspan="${OLD_FIELDS.length}">Παλιά μέλη</th><th></th></tr>` : ""}
      <tr><th>Εργαζόμενος</th>${kind !== "exclusive" ? `<th class="r calc">Ενημερ.</th>` : ""}${K.fields.map((f) => `<th class="r" title="${h(FIELD_LABEL[f])}">${h(FIELD_SHORT[f])}</th>`).join("")}${K.metrics.map((m) => `<th class="r calc" title="${h(m.formula)}">${h(m.label)}</th>`).join("")}${old ? OLD_FIELDS.map((f) => `<th class="r old" title="${h(FIELD_LABEL[f])}">${h(FIELD_SHORT[f])}</th>`).join("") : ""}<th></th></tr></thead><tbody>
      ${list.map((k) => `<tr data-key="${h(k.e.code)}|${h(k.spec)}" data-kind="${kind}">
        <td><strong>${h(k.e.last)} ${h(k.e.first)}</strong><span class="sub">${h(k.e.code)}${k.row ? ` · ${k.row.updated_at ? "διορθώθηκε " + athens(k.row.updated_at) : "καταχωρίστηκε " + athens(k.row.created_at)}` : " · χωρίς καταχώριση"}</span></td>
        ${kind !== "exclusive" ? `<td class="r num calc" data-out="informed">—</td>` : ""}
        ${K.fields.map((f) => `<td><input class="cnt" inputmode="numeric" data-f="${f}" value="${k.row ? k.row[f] : ""}" aria-label="${h(FIELD_LABEL[f])}"></td>`).join("")}
        ${K.metrics.map((m) => `<td class="r num calc" data-out="${m.key}">—</td>`).join("")}
        ${old ? OLD_FIELDS.map((f) => `<td class="old"><input class="cnt" inputmode="numeric" data-f="${f}" data-old="1" value="${k.row && k.row[f] !== null && k.row[f] !== undefined ? k.row[f] : ""}" aria-label="${h(FIELD_LABEL[f])}"></td>`).join("") : ""}
        <td>${k.row ? `<button class="btn sm ghost" data-hist="${k.row.id}" title="Ιστορικό διορθώσεων">↺</button>` : ""}</td></tr>`).join("")}
      </tbody></table></div></div>`;
  };

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Στατιστικά</div><h1>Καθημερινή καταχώριση</h1>
    <p class="muted">Συμπληρώστε τα αρχικά μεγέθη· οι ενημερώσεις (DR + LOST) και τα ποσοστά υπολογίζονται αυτόματα. Κενή γραμμή = χωρίς καταχώριση· για ημέρα χωρίς αποτελέσματα γράψτε 0.</p></div>
    <div class="row-actions">${P("stats.links") ? `<button class="btn" id="se-links">Σύνδεσμοι Ρεσεψιόν</button>` : ""}${can.statsReports() ? `<a class="btn" href="#/stats-report">Αναφορές</a>` : ""}</div></div>
  <div class="card"><div class="toolbar">
    <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Ημερομηνία <input type="date" id="se-date" max="${athensToday()}" value="${F.date}" style="width:auto"></label>
    ${role() === "manager" ? `<strong>${h(F.store)}</strong>` : `<select id="se-store">${activeStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>`}
    <span class="spacer"></span><span id="se-dirty" class="muted small"></span><button class="btn primary" id="se-save">Αποθήκευση</button></div>
    ${noSpec.length ? `<div class="note warn">Χωρίς ειδικότητα με στατιστικά (δεν εμφανίζονται): ${noSpec.map((e) => h(`${e.last} ${e.first}`)).join(", ")}. Η ειδικότητα ορίζεται από το HR.</div>` : ""}
    ${keyed.length ? "" : `<div class="empty">Δεν υπάρχουν ενεργοί εργαζόμενοι με ειδικότητα Ρεσεψιόν, Επίβλεψη ή Exclusive στο κατάστημα.</div>`}
  </div>
  ${["reception", "supervision", "exclusive"].map(section).join("")}
  <p id="se-msg" class="form-msg"></p>`;

  const rowState = (tr) => {
    const kind = tr.dataset.kind, vals = {}; let empty = 0, oldEmpty = 0, err = null;
    for (const inp of $$(".cnt", tr)) {
      const p = parseCount(inp.value);
      inp.classList.toggle("bad", !!p.error);
      if (p.error) err = p.error; else if (p.empty) { if (inp.dataset.old) oldEmpty++; else empty++; } else vals[inp.dataset.f] = p.value;
    }
    const n = KINDS[kind].fields.length, no = oldFieldsFor(kind).length;
    return { kind, vals, err, empty: empty === n && oldEmpty === no, partial: (empty > 0 && empty < n) || (oldEmpty > 0 && oldEmpty < no) || (empty === n && oldEmpty < no),
             oldEmpty: no > 0 && oldEmpty === no };
  };
  const recalc = (tr) => {
    const st = rowState(tr);
    const t = st.empty || st.partial || st.err ? null : totals([{ kind: st.kind, ...st.vals }], st.kind);
    const m = t ? metrics(t, st.kind) : null;
    $$("[data-out]", tr).forEach((td) => (td.textContent = !t ? "—" : td.dataset.out === "informed" ? t.informed : fmtPct(m[td.dataset.out])));
    tr.classList.toggle("partial", st.partial);
  };
  $$("tr[data-key]").forEach((tr) => { recalc(tr); $$(".cnt", tr).forEach((i) => (i.oninput = () => { recalc(tr); $("#se-dirty").textContent = "Μη αποθηκευμένες αλλαγές"; })); });
  $("#se-date").onchange = (e) => { F.date = e.target.value; statsEntry(params); };
  $("#se-store") && ($("#se-store").onchange = (e) => { F.store = e.target.value; statsEntry(params); });
  $$("[data-hist]").forEach((b) => (b.onclick = () => historyDialog(Number(b.dataset.hist))));
  $("#se-links") && ($("#se-links").onclick = () => linksDialog());
  $("#se-save").onclick = async () => {
    const payload = []; const problems = [];
    for (const tr of $$("tr[data-key]")) {
      const st = rowState(tr), [code, spec] = tr.dataset.key.split("|");
      const k = keyed.find((x) => x.e.code === code && x.spec === spec);
      if (st.err) { problems.push(`${code}: ${st.err}`); continue; }
      if (st.partial) { problems.push(`${code}: συμπληρώστε όλα τα πεδία ή κανένα`); continue; }
      if (st.empty) { if (k.row) problems.push(`${code}: η υπάρχουσα καταχώριση δεν διαγράφεται· διορθώστε τις τιμές`); continue; }
      const legacy = k.row && isUnsplit(k.row);
      if (st.oldEmpty && !legacy) { problems.push(`${code}: συμπληρώστε και τα «Παλιά μέλη» (0 όπου δεν υπάρχουν)`); continue; }
      if (k.row) {
        if (KINDS[st.kind].fields.every((f) => Number(k.row[f]) === st.vals[f]) && oldFieldsFor(st.kind).every((f) => (k.row[f] ?? null) === (st.vals[f] ?? null))) continue;
        payload.push({ id: k.row.id, version: k.row.version, employee_code: code, ...st.vals });
      } else if (!k.readonlyNew) payload.push({ employee_code: code, ...st.vals });
    }
    if (problems.length) return ($("#se-msg").innerHTML = problems.map(h).join("<br>"));
    if (!payload.length) return toast("Δεν υπάρχουν αλλαγές.");
    const btn = $("#se-save"); btn.disabled = true;
    try {
      const res = await S.api.statsSave(F.date, payload);
      const bad = res.rows.filter((r) => !r.ok);
      invalidate(); await statsEntry(params);
      if (bad.length) { $("#se-msg").innerHTML = bad.map((r) => `${h(r.employee_code)}: ${h(r.error)}`).join("<br>"); toast(`Αποθηκεύτηκαν ${res.rows.length - bad.length}, απορρίφθηκαν ${bad.length}.`, true); }
      else toast(`Αποθηκεύτηκαν ${res.rows.length} γραμμές.`);
    } catch (e) { $("#se-msg").textContent = e.message; btn.disabled = false; }
  };
}

async function historyDialog(id) {
  const list = await S.api.statsHistory(id);
  openDialog(`<div class="dlg-head"><h2>Ιστορικό διορθώσεων</h2><button class="icon-btn" data-close>✕</button></div>
    ${list.length ? list.map((x) => `<div class="list-item"><div class="grow"><div class="small">${Object.keys(x.new_values).filter((k) => x.old_values[k] !== x.new_values[k]).map((k) => `${FIELD_SHORT[k]}: ${x.old_values[k]} → <strong>${x.new_values[k]}</strong>`).join(" · ")}</div>
      <div class="muted small">${h(x.changed_by)} · ${athens(x.changed_at)}</div></div></div>`).join("") : `<p class="muted">Δεν έχει διορθωθεί.</p>`}
    <div class="dlg-foot"><button class="btn primary" data-close>Κλείσιμο</button></div>`);
}

// ═══════════════════════ Αναφορές διαστήματος ═══════════════════════
export async function statsReport(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αναφορές στατιστικών"));
  if (!can.statsReports()) return (view().innerHTML = `<div class="card empty">Δεν έχετε πρόσβαση στις αναφορές στατιστικών.</div>`);
  const today = athensToday();
  const F = (S.filters.statsRep ??= { from: today.slice(0, 8) + "01", to: today, store: "", kind: "reception", tab: "emp", metric: "conv" });
  if (F.to < F.from) F.to = F.from;
  const [rows0, emps] = await Promise.all([S.api.stats({ from: F.from, to: F.to, store: F.store || undefined }), getEmployees()]);
  const rows = KINDS[F.kind]?.old ? oldMemberRows(rows0, baseKind(F.kind)) : rows0.filter((r) => r.kind === F.kind);
  const K = KINDS[F.kind];
  if (!K.metrics.some((m) => m.key === F.metric)) F.metric = K.metrics[0].key;
  const name = (code) => { const e = emps.find((x) => x.code === code); return e ? `${e.last} ${e.first}` : code; };
  const days = daysBetween(F.from, F.to);
  const head = `${baseKind(F.kind) !== "exclusive" ? "<th class='r'>Ενημερώσεις</th>" : ""}${K.fields.map((f) => `<th class="r" title="${h(FIELD_LABEL[f])}">${h(FIELD_SHORT[f])}</th>`).join("")}${baseKind(F.kind) !== "exclusive" ? "<th class='r' title='DR + CB'>Εγγραφές</th>" : ""}${K.metrics.map((m) => `<th class="r" title="${h(m.formula)}">${h(m.label)}</th>`).join("")}`;
  const cells = (t) => { const m = metrics(t, F.kind); return `${baseKind(F.kind) !== "exclusive" ? `<td class="r num">${t.informed}</td>` : ""}${K.fields.map((f) => `<td class="r num">${t[f]}</td>`).join("")}${baseKind(F.kind) !== "exclusive" ? `<td class="r num"><strong>${t.total_enr}</strong></td>` : ""}${K.metrics.map((x) => `<td class="r num">${fmtPct(m[x.key])}</td>`).join("")}`; };
  const warnCell = (t) => { const w = warnings(t, F.kind); return w.length ? `<span class="warn-dot" title="${h(w.join("\n"))}">⚠</span>` : ""; };

  let content = "";
  if (F.tab === "emp") {
    const g = groupBy(rows, (r) => `${r.employee_code}|${r.store}`);
    content = `<div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Κατάστημα</th><th class="r">Ημέρες</th>${head}<th></th></tr></thead><tbody>
      ${[...g].sort((a, b) => name(a[1][0].employee_code).localeCompare(name(b[1][0].employee_code), "el")).map(([, rs]) => { const t = totals(rs, F.kind); return `<tr><td><a href="#/employee?code=${encodeURIComponent(rs[0].employee_code)}&tab=stats&from=${F.from}&to=${F.to}">${h(name(rs[0].employee_code))}</a><span class="sub">${h(rs[0].employee_code)}</span></td><td>${h(rs[0].store)}</td><td class="r num">${t.days}/${days.length}</td>${cells(t)}<td>${warnCell(t)}</td></tr>`; }).join("")}
      </tbody></table></div>`;
  } else if (F.tab === "store") {
    const g = groupBy(rows, (r) => r.store);
    content = `<p class="muted small" style="margin-bottom:10px">Συγκεντρωτικά ανά κατάστημα για την ειδικότητα <strong>${K.label}</strong>. Δεν αθροίζονται διαφορετικές ειδικότητες, ώστε να μη διπλομετρηθούν εγγραφές.</p>
      <div class="table-wrap"><table class="stack"><thead><tr><th>Κατάστημα</th><th class="r">Εργαζόμενοι</th><th class="r">Καταχωρίσεις</th>${head}<th></th></tr></thead><tbody>
      ${[...g].map(([st, rs]) => { const t = totals(rs, F.kind); return `<tr><td><strong>${h(st)}</strong></td><td class="r num">${new Set(rs.map((r) => r.employee_code)).size}</td><td class="r num">${rs.length}</td>${cells(t)}<td>${warnCell(t)}</td></tr>`; }).join("")}
      ${g.size > 1 ? (() => { const t = totals(rows, F.kind); return `<tr class="total"><td><strong>Όλα τα καταστήματα · ${K.label}</strong></td><td class="r num">${new Set(rows.map((r) => r.employee_code)).size}</td><td class="r num">${rows.length}</td>${cells(t)}<td>${warnCell(t)}</td></tr>`; })() : ""}
      </tbody></table></div>`;
  } else if (F.tab === "daily") {
    const people = [...new Set(rows.map((r) => r.employee_code))];
    const by = Object.fromEntries(rows.map((r) => [`${r.employee_code}|${r.stat_date}`, r]));
    const shownDays = days.slice(-62);
    content = `${days.length > 62 ? `<p class="note" style="margin-bottom:10px">Εμφανίζονται οι τελευταίες 62 ημέρες${can.statsExport() ? "· το Excel περιέχει όλες" : ""}.</p>` : ""}
      <p class="muted small" style="margin-bottom:10px"><span class="cell-missing">·</span> = χωρίς καταχώριση (διαφορετικό από το 0). Τιμή κελιού: ${baseKind(F.kind) === "exclusive" ? "Δοκιμαστικά / Εγγραφές" : "Ενημερώσεις / Εγγραφές (DR+CB)"}.</p>
      <div class="table-wrap"><table class="daily"><thead><tr><th>Εργαζόμενος</th>${shownDays.map((d) => `<th class="r">${d.slice(8)}/${d.slice(5, 7)}</th>`).join("")}</tr></thead><tbody>
      ${people.map((p) => `<tr><td>${h(name(p))}</td>${shownDays.map((d) => { const r = by[`${p}|${d}`]; return r ? `<td class="r num">${baseKind(F.kind) === "exclusive" ? `${r.trials_done}/${r.enr_from_trials}` : `${r.informed}/${r.dr + r.cb}`}</td>` : `<td class="r cell-missing">·</td>`; }).join("")}</tr>`).join("")}
      </tbody></table></div>`;
  } else {
    const n = days.length;
    const g = groupBy(rows, (r) => bucketOf(r.stat_date, n));
    const keys = [...new Set(days.map((d) => bucketOf(d, n)))];
    const series = keys.map((k) => { const rs = g.get(k) || []; return { k, v: rs.length ? metrics(totals(rs, F.kind), F.kind)[F.metric] : null, n: rs.length }; });
    content = `<div class="toolbar"><select id="sr-metric">${K.metrics.map((m) => `<option value="${m.key}" ${m.key === F.metric ? "selected" : ""}>${h(m.label)} (${h(m.formula)})</option>`).join("")}</select>
      <span class="muted small">Ανά ${n <= 45 ? "ημέρα" : n <= 210 ? "εβδομάδα (από Δευτέρα)" : "μήνα"} · κάθε σημείο από τα αθροίσματα της περιόδου του · κενό = χωρίς καταχωρίσεις ή μηδενικός παρονομαστής</span></div>
      ${lineChart(series, n)}`;
  }

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Στατιστικά</div><h1>Αναφορές διαστήματος</h1>
    <p class="muted">Από ${dmy(F.from)} έως και ${dmy(F.to)} (${days.length} ημέρες). Τα ποσοστά υπολογίζονται από τα αθροίσματα, όχι ως μέσος όρος ημερήσιων ποσοστών. Δεν υπάρχουν στόχοι ή συνολική βαθμολογία.</p></div>
    <div class="row-actions">${can.statsEntry() ? `<a class="btn" href="#/stats-entry">Καταχώριση</a>` : ""}${can.statsExport() ? `<button class="btn" id="sr-xlsx">⇩ Excel</button>` : ""}</div></div>
  <div class="card">
    <div class="toolbar">
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Από <input type="date" id="sr-from" value="${F.from}" style="width:auto"></label>
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Έως <input type="date" id="sr-to" value="${F.to}" style="width:auto"></label>
      ${role() === "manager" ? `<strong>${h(S.me.store)}</strong>` : `<select id="sr-store"><option value="">Όλα τα καταστήματα</option>${visibleStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>`}
      <div class="chips">${Object.entries(KINDS).map(([k, v]) => `<button class="chip ${k === F.kind ? "on" : ""}" data-kind="${k}">${v.label}</button>`).join("")}</div>
    </div>
    <div class="tabs">${[["emp", "Ανά εργαζόμενο"], ["store", "Ανά κατάστημα"], ["daily", "Ημερήσιες καταχωρίσεις"], ["trend", "Εξέλιξη"], ["members", "Νέες εγγραφές & ανανεώσεις"]].map(([k, l]) => `<a href="javascript:void 0" data-tab="${k}" class="${k === F.tab ? "on" : ""}">${l}</a>`).join("")}</div>
    ${F.tab === "members" ? `<div id="sr-members"><div class="spinner"></div></div>` : rows.length ? content : `<div class="empty">Δεν υπάρχουν καταχωρίσεις ${K.label} στο διάστημα.</div>`}
  </div>`;
  const re = () => statsReport(params);
  if (F.tab === "members") membersReport(F);
  $("#sr-from").onchange = (e) => { F.from = e.target.value; re(); };
  $("#sr-to").onchange = (e) => { F.to = e.target.value; re(); };
  $("#sr-store") && ($("#sr-store").onchange = (e) => { F.store = e.target.value; re(); });
  $$("[data-kind]").forEach((b) => (b.onclick = () => { F.kind = b.dataset.kind; re(); }));
  $$("[data-tab]").forEach((b) => (b.onclick = () => { F.tab = b.dataset.tab; re(); }));
  $("#sr-metric") && ($("#sr-metric").onchange = (e) => { F.metric = e.target.value; re(); });
  $("#sr-xlsx") && ($("#sr-xlsx").onclick = () => {
    const hdr = ["Κωδικός", "Εργαζόμενος", "Κατάστημα", "Ειδικότητα", ...(baseKind(F.kind) !== "exclusive" ? ["Ενημερώσεις"] : []), ...K.fields.map((f) => FIELD_LABEL[f]), ...(baseKind(F.kind) !== "exclusive" ? ["Εγγραφές (DR+CB)"] : []), ...K.metrics.map((m) => `${m.label} %`)];
    const line = (t) => { const m = metrics(t, F.kind); return [...(baseKind(F.kind) !== "exclusive" ? [t.informed] : []), ...K.fields.map((f) => t[f]), ...(baseKind(F.kind) !== "exclusive" ? [t.total_enr] : []), ...K.metrics.map((x) => (m[x.key] === null ? "—" : Math.round(m[x.key] * 10) / 10))]; };
    const perEmp = [...groupBy(rows, (r) => `${r.employee_code}|${r.store}`)].map(([, rs]) => [rs[0].employee_code, name(rs[0].employee_code), rs[0].store, rs[0].specialty, ...line(totals(rs, F.kind))]);
    const perStore = [...groupBy(rows, (r) => r.store)].map(([st, rs]) => ["", "", st, K.label, ...line(totals(rs, F.kind))]);
    const daily = rows.map((r) => [dmy(r.stat_date), r.employee_code, name(r.employee_code), r.store, r.specialty, ...(baseKind(F.kind) !== "exclusive" ? [r.informed] : []), ...K.fields.map((f) => r[f]), r.created_by, r.updated_by || ""]);
    downloadXlsx(`Στατιστικά_${K.label}_${F.from}_${F.to}.xlsx`, {
      "Ανά εργαζόμενο": [hdr, ...perEmp], "Ανά κατάστημα": [hdr, ...perStore],
      "Ημερήσιες": [["Ημερομηνία", "Κωδικός", "Εργαζόμενος", "Κατάστημα", "Ειδικότητα", ...(baseKind(F.kind) !== "exclusive" ? ["Ενημερώσεις"] : []), ...K.fields.map((f) => FIELD_LABEL[f]), "Καταχώρισε", "Διόρθωσε"], ...daily],
    });
  });
}

function lineChart(series, n) {
  const W = 760, H = 260, L = 44, R = 12, T = 14, B = 34;
  const vals = series.map((s) => s.v).filter((v) => v !== null);
  if (!vals.length) return `<div class="empty">Δεν υπάρχουν τιμές για τον δείκτη στο διάστημα.</div>`;
  const max = Math.max(10, Math.ceil(Math.max(...vals) / 10) * 10);
  const x = (i) => L + (series.length === 1 ? (W - L - R) / 2 : (i * (W - L - R)) / (series.length - 1));
  const y = (v) => T + (H - T - B) * (1 - v / max);
  let path = "", pen = false;
  series.forEach((s, i) => { if (s.v === null) { pen = false; return; } path += `${pen ? "L" : "M"}${x(i).toFixed(1)},${y(s.v).toFixed(1)} `; pen = true; });
  const lab = (k) => (k.length === 7 ? `${k.slice(5)}/${k.slice(2, 4)}` : `${k.slice(8)}/${k.slice(5, 7)}`);
  const step = Math.max(1, Math.ceil(series.length / 10));
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Εξέλιξη δείκτη">
    ${[0, 0.25, 0.5, 0.75, 1].map((f) => `<line x1="${L}" x2="${W - R}" y1="${y(max * f)}" y2="${y(max * f)}" class="grid-l"/><text x="${L - 6}" y="${y(max * f) + 4}" text-anchor="end" class="ax">${Math.round(max * f)}%</text>`).join("")}
    <path d="${path}" class="line"/>
    ${series.map((s, i) => (s.v === null ? "" : `<circle cx="${x(i)}" cy="${y(s.v)}" r="3.5" class="pt"><title>${lab(s.k)}: ${fmtPct(s.v)} (${s.n} καταχωρίσεις)</title></circle>`)).join("")}
    ${series.map((s, i) => (i % step === 0 ? `<text x="${x(i)}" y="${H - 12}" text-anchor="middle" class="ax">${lab(s.k)}</text>` : "")).join("")}
  </svg>`;
}


// Νέες εγγραφές (νέα μέλη) και ανανεώσεις (παλιά μέλη) ανά κατάστημα και συνολικά, για οποιοδήποτε διάστημα και είδος.
// Ρεσεψιόν / Επίβλεψη: DR + CB · Exclusive: εγγραφές από δοκιμαστικά. Ανανεώσεις = παλιά μέλη + «Άμεσο» (ξεχωριστό μέγεθος).
async function membersReport(F) {
  const el = $("#sr-members"); if (!el) return;
  const kind = baseKind(F.kind), excl = kind === "exclusive";
  try {
    const R = await S.api.statsMembers(F.from, F.to, F.store, kind);
    const sum = (k) => R.reduce((a, r) => a + Number(r[k] || 0), 0);
    const row = (label, g, strong) => `<tr class="${strong ? "total" : ""}"><td>${strong ? `<strong>${h(label)}</strong>` : h(label)}</td><td class="r num">${g("new_enrolled")}</td>
      <td class="r num">${g("old_enrolled")}</td><td class="r num">${g("old_direct")}</td><td class="r num">${g("renewals")}</td><td class="r num"><strong>${g("grand_total")}</strong></td>
      ${excl ? "" : `<td class="r num muted">${g("new_informed")} / ${g("old_informed")}</td>`}<td class="r num">${g("rows_unsplit") ? `${g("rows_unsplit")} ημ. · ${g("unsplit_enrolled")} εγγρ.` : "—"}</td></tr>`;
    const f = excl ? "εγγρ. από δοκιμαστικά" : "DR + CB";
    el.innerHTML = `<p class="muted small" style="margin:8px 0">${h(KINDS[kind].label)}</p>` + (R.length ? `<div class="table-wrap"><table><thead><tr><th>Κατάστημα</th><th class="r">Νέες εγγραφές<br><span class="muted small">νέα μέλη · ${f}</span></th>
      <th class="r">Παλιά μέλη<br><span class="muted small">${f}</span></th><th class="r">Παλιά μέλη — Άμεσο</th><th class="r">Ανανεώσεις<br><span class="muted small">παλιά μέλη + Άμεσο</span></th><th class="r">Γενικό σύνολο</th>
      ${excl ? "" : `<th class="r">Ενημερώσεις νέων / παλιών<br><span class="muted small">DR + LOST · όχι εγγραφές</span></th>`}<th class="r">Χωρίς διάκριση<br><span class="muted small">παλιές καταχωρίσεις</span></th></tr></thead><tbody>
      ${R.map((r) => row(r.store, (k) => r[k] ?? 0)).join("")}${R.length > 1 ? row("Όλα τα καταστήματα", sum, true) : ""}</tbody></table></div>
      <p class="muted small" style="margin-top:8px">Το «Παλιά μέλη — Άμεσο» είναι ξεχωριστό μέγεθος (δεν περιέχεται στο DR) και προστίθεται στις ανανεώσεις. Οι παλιές καταχωρίσεις (πριν από τη διάκριση νέων/παλιών) δεν κατατάσσονται σε καμία ομάδα.</p>`
      : `<div class="empty">Δεν υπάρχουν καταχωρίσεις στο διάστημα.</div>`);
  } catch (e) { el.innerHTML = `<div class="note bad">${h(e.message)}</div>`; }
}

// Σύνδεσμοι στατιστικών Ρεσεψιόν ανά κατάστημα: δημιουργία / αντικατάσταση / ανάκληση. Το κλειδί εμφανίζεται ΜΟΝΟ μία φορά.
async function linksDialog(fresh) {
  let list;
  try { list = await S.api.statLinks(); } catch (e) { return toast(e.message, true); }
  const active = Object.fromEntries(list.filter((x) => x.status === "active").map((x) => [x.store, x]));
  const base = location.href.split("#")[0].replace(/index\.html$/, "");
  openDialog(`<div class="dlg-head"><h2>Σύνδεσμοι στατιστικών Ρεσεψιόν</h2><button class="icon-btn" data-close>✕</button></div>
    <p class="muted small">Ένας σύνδεσμος ανά κατάστημα, μόνο για υποβολή ημερήσιων στατιστικών Ρεσεψιόν. Δεν δείχνει προηγούμενες εγγραφές ή άλλες ενότητες. Η «Αντικατάσταση» ακυρώνει αμέσως τον προηγούμενο σύνδεσμο.</p>
    ${fresh ? `<div class="note"><strong>Νέος σύνδεσμος ${h(fresh.store)}</strong> (εμφανίζεται μόνο τώρα — αντιγράψτε τον):<br><input id="lk-url" readonly value="${h(base + "s.html#" + fresh.token)}" style="margin-top:6px"><button class="btn sm" id="lk-copy" style="margin-top:6px">Αντιγραφή</button></div>` : ""}
    ${visibleStores().map((st) => { const a = active[st]; return `<div class="list-item"><div class="grow"><strong>${h(st)}</strong><div class="muted small">${a ? `Ενεργός από ${athens(a.created_at)} · ${a.submissions} υποβολές${a.last_used_at ? ` · τελευταία ${athens(a.last_used_at)}` : ""}` : "Χωρίς ενεργό σύνδεσμο"}</div></div>
      <button class="btn sm" data-new="${h(st)}">${a ? "Αντικατάσταση" : "Δημιουργία"}</button>${a ? `<button class="btn sm danger" data-rev="${h(st)}">Ανάκληση</button>` : ""}</div>`; }).join("")}
    <div class="dlg-foot"><button class="btn primary" data-close>Κλείσιμο</button></div>`, {
    onOpen() {
      $("#lk-copy") && ($("#lk-copy").onclick = async () => { try { await navigator.clipboard.writeText($("#lk-url").value); toast("Αντιγράφηκε."); } catch { $("#lk-url").select(); } });
      $$("[data-new]").forEach((b) => (b.onclick = async () => { try { const r = await S.api.statLinkCreate(b.dataset.new); linksDialog({ store: b.dataset.new, token: r.token }); } catch (e) { toast(e.message, true); } }));
      $$("[data-rev]").forEach((b) => (b.onclick = async () => { try { await S.api.statLinkRevoke(b.dataset.rev); toast("Ο σύνδεσμος ανακλήθηκε."); linksDialog(); } catch (e) { toast(e.message, true); } }));
    },
  });
}
