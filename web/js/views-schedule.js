// Πρόγραμμα προσωπικού: κατακόρυφο χρονοδιάγραμμα ανά ημέρα (κάθε εργαζόμενος μια στήλη, ώρες αριστερά ανά μισάωρο),
// κάλυψη ανά μισάωρο, άδειες/απουσίες/αποχωρήσεις, εβδομαδιαίες ώρες, σταθερό/προσωρινό/μόνιμο/σπαστό ωράριο,
// οριστικοποίηση με υποχρεωτική αιτιολογία μετά, ιστορικό. Όλοι οι υπολογισμοί γίνονται στον server (sched_week).
import { S, can, role, visibleStores, activeSpecialties } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, dmy } from "./util.js";
import { athens, athensToday, demoNotice } from "./hr-common.js";
import { empColor, num2 } from "./views-leave.js";

const view = () => $("#view");
const DOW = ["Δευτέρα", "Τρίτη", "Τετάρτη", "Πέμπτη", "Παρασκευή", "Σάββατο", "Κυριακή"];
const DOW_S = ["Δε", "Τρ", "Τε", "Πε", "Πα", "Σα", "Κυ"];
const ROW = 22;   // ύψος μισάωρου (px)
const toMin = (t) => { const [a, b] = String(t).split(":").map(Number); return a * 60 + b; };
const addDays = (d, n) => { const x = new Date(d + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const mondayOf = (d) => { const x = new Date(d + "T12:00:00Z"); const wd = (x.getUTCDay() + 6) % 7; return addDays(d, -wd); };
export const segText = (s) => (s?.length ? s.map((x) => `${x[0]}–${x[1]}`).join(" · ") : "—");
const CHANGE_GR = { permanent: "Μόνιμη αλλαγή", temporary: "Προσωρινή αλλαγή", temporary_cleared: "Επαναφορά στο σταθερό", finalize: "Οριστικοποίηση εβδομάδας", transfer: "Μόνιμη μεταφορά" };

export async function schedule(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Πρόγραμμα"));
  const stores = visibleStores();
  const F = (S.filters.sched ??= { store: role() === "manager" ? S.me.store : stores[0], week: mondayOf(athensToday()), day: athensToday(), spec: "" });
  if (!stores.includes(F.store)) F.store = stores[0];
  if (params.get("week")) { F.week = mondayOf(params.get("week")); F.day = params.get("week"); }
  if (F.day < F.week || F.day > addDays(F.week, 6)) F.day = F.week;
  if (!F.store) return (view().innerHTML = `<div class="card empty">Δεν υπάρχει κατάστημα στο πεδίο σας.</div>`);
  const w = await S.api.schedWeek(F.store, F.week, F.spec);
  const manage = w.can_manage;
  const cov = w.coverage[F.day] || [];
  const uncovered = (d) => (w.coverage[d] || []).some((x) => x.uncovered);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Πρόγραμμα προσωπικού · ${h(F.store)}</div><h1>Εβδομάδα ${dmy(F.week)} – ${dmy(addDays(F.week, 6))}</h1>
    <p class="muted">${w.finalized ? `<span class="badge b-signed">Οριστικοποιήθηκε</span> από ${h(w.finalized.by)} · ${athens(w.finalized.at)}. Κάθε αλλαγή χρειάζεται αιτιολογία και καταγράφεται.` : `<span class="badge b-missing">Μη οριστικοποιημένο</span> ${manage ? "Ο manager δημιουργεί, αλλάζει και οριστικοποιεί χωρίς έγκριση HR/ΓΔ." : ""}`}</p></div>
    <div class="row-actions">
      ${manage && !w.finalized ? `<button class="btn primary" id="sc-final">Οριστικοποίηση εβδομάδας</button>` : ""}
      <button class="btn" id="sc-hist">Ιστορικό αλλαγών</button>
      ${can.scheduleSettings() ? `<button class="btn" id="sc-set">⚙ Ωράρια λειτουργίας & έτοιμα ωράρια</button>` : ""}
    </div></div>
  <div class="card">
    <div class="toolbar">
      ${stores.length > 1 ? `<select id="sc-store">${stores.map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>` : ""}
      <select id="sc-spec"><option value="">Όλα τα τμήματα</option>${activeSpecialties().map((s) => `<option ${s === F.spec ? "selected" : ""}>${h(s)}</option>`).join("")}</select>
      <button class="btn sm" id="sc-prev" aria-label="Προηγούμενη εβδομάδα">◀</button>
      <input type="date" id="sc-date" value="${F.day}" style="width:auto">
      <button class="btn sm" id="sc-next" aria-label="Επόμενη εβδομάδα">▶</button>
    </div>
    <div class="tabs sc-days">${w.days.map((d, i) => `<a href="javascript:void 0" data-day="${d}" class="${d === F.day ? "on" : ""}">${DOW_S[i]} ${d.slice(8)}/${d.slice(5, 7)}${uncovered(d) ? ` <span class="dot-bad" title="Υπάρχει διάστημα χωρίς κανέναν διαθέσιμο">●</span>` : ""}${w.holidays[d] ? ` <span class="muted small">(${h(w.holidays[d])})</span>` : ""}</a>`).join("")}</div>
    ${timeline(w, F.day, cov, manage)}
    <div class="legend" style="margin-top:10px">
      <span><i style="background:#2a7"></i>Πρόγραμμα (χρώμα ανά εργαζόμενο)</span><span><i class="lg-temp"></i>Προσωρινή αλλαγή</span><span><i class="lg-leave"></i>Άδεια / απουσία — δεν μετρά</span>
      <span><i class="lg-gone"></i>Μετά την αποχώρηση</span><span><i style="background:var(--bad)"></i>Κανένας διαθέσιμος σε ώρα λειτουργίας</span><span>⏳ Άδεια σε αναμονή (μετρά στην κάλυψη)</span><span>⚠ Επικαλυπτόμενα διαστήματα</span>
    </div>
    <p class="muted small" style="margin-top:6px">Η κάλυψη μετρά όσους είναι προγραμματισμένοι στην αρχή κάθε μισάωρου, χωρίς όσους είναι σε εγκεκριμένη άδεια ή έχουν αποχωρήσει. Υπο-/υπερστελέχωση εμφανίζεται μόνο όπου έχουν οριστεί απαιτήσεις κάλυψης.</p>
  </div>
  ${w.needs_cover.length ? `<div class="card" style="margin-top:16px"><div class="card-head"><h3>Βάρδιες που χρειάζονται κάλυψη</h3></div>
    ${w.needs_cover.map((x) => `<div class="list-item"><div class="grow"><strong>${h(x.employee_name)}</strong> · ${DOW[(new Date(x.day + "T12:00:00Z").getUTCDay() + 6) % 7]} ${dmy(x.day)} · ${segText(x.segments)}</div><span class="badge b-pending">${h(x.why)}</span></div>`).join("")}
    <p class="muted small" style="margin-top:8px">Καμία αυτόματη αντικατάσταση: ο manager επιλέγει ποιος καλύπτει (προσωρινή αλλαγή).</p></div>` : ""}
  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Εβδομαδιαίες ώρες</h3></div>
    <div class="table-wrap"><table class="stack"><thead><tr><th>Εργαζόμενος</th><th>Σύστημα</th><th class="r">Συμβατικές</th><th class="r">Προγραμματισμένη εργασία</th><th class="r">Ώρες σε άδεια</th><th class="r">Απόκλιση</th></tr></thead><tbody>
    ${w.employees.map((e) => `<tr><td><span class="sw" style="background:${empColor(e.code)}"></span><strong>${h(e.name)}</strong><span class="sub">${h(e.specialty || "—")}${e.leave_date ? ` · αποχώρηση ${dmy(e.leave_date)}` : ""}</span></td>
      <td>${e.work_week ? (e.work_week === 6 ? "Εξαήμερο" : "Πενθήμερο") : `<span class="badge b-missing">Λείπει</span>`}</td><td class="r num">${e.contract_hours ? num2(e.contract_hours) : "—"}</td>
      <td class="r num">${num2(e.planned_hours)}</td><td class="r num">${Number(e.leave_hours) ? num2(e.leave_hours) : "—"}</td>
      <td class="r num">${e.deviation === null ? "—" : `${Number(e.deviation) > 0 ? "+" : ""}${num2(e.deviation)}`}${e.has_leave && Number(e.deviation) < 0 ? `<span class="sub">εβδομάδα με άδεια — όχι υποχρέωση αναπλήρωσης</span>` : ""}</td></tr>`).join("") || `<tr><td colspan="6" class="muted">Δεν υπάρχουν εργαζόμενοι.</td></tr>`}
    </tbody></table></div></div>`;

  const re = () => schedule(new URLSearchParams());
  $("#sc-store") && ($("#sc-store").onchange = (e) => { F.store = e.target.value; re(); });
  $("#sc-spec").onchange = (e) => { F.spec = e.target.value; re(); };
  $("#sc-prev").onclick = () => { F.week = addDays(F.week, -7); F.day = addDays(F.day, -7); re(); };
  $("#sc-next").onclick = () => { F.week = addDays(F.week, 7); F.day = addDays(F.day, 7); re(); };
  $("#sc-date").onchange = (e) => { if (!e.target.value) return; F.day = e.target.value; F.week = mondayOf(F.day); re(); };
  $$("[data-day]").forEach((a) => (a.onclick = () => { F.day = a.dataset.day; re(); }));
  $("#sc-final") && ($("#sc-final").onclick = async () => {
    try { await S.api.schedFinalize(F.store, F.week); toast("Η εβδομάδα οριστικοποιήθηκε."); re(); } catch (e) { toast(e.message, true); }
  });
  $("#sc-hist").onclick = () => historyDialog(F.store, F.week);
  $("#sc-set") && ($("#sc-set").onclick = () => settingsDialog(F.store));
  $$("[data-emp]").forEach((b) => (b.onclick = () => employeeDialog(w, w.employees.find((e) => e.code === b.dataset.emp), F, re)));
}

function timeline(w, day, cov, manage) {
  const emps = w.employees;
  if (!emps.length) return `<div class="empty">Δεν υπάρχουν εργαζόμενοι για το κατάστημα/τμήμα.</div>`;
  const slots = cov.length ? cov : Array.from({ length: 32 }, (_, i) => ({ slot: `${String(6 + Math.floor(i / 2)).padStart(2, "0")}:${i % 2 ? "30" : "00"}`, count: 0 }));
  const lo = toMin(slots[0].slot), hi = toMin(slots[slots.length - 1].slot) + 30;
  const H = ((hi - lo) / 30) * ROW;
  const hours = w.hours[day];
  const col = (e) => {
    const d = e.days[day] || {};
    const c = empColor(e.code);
    const bars = (d.segments || []).map((s) => {
      const top = ((toMin(s[0]) - lo) / 30) * ROW, ht = Math.max(((toMin(s[1]) - toMin(s[0])) / 30) * ROW, 6);
      const cls = d.leave ? "leave" : d.departed ? "gone" : d.source === "temporary" ? "temp" : "";
      return `<div class="sc-bar ${cls} ${d.overlap ? "ovl" : ""}" style="top:${top}px;height:${ht}px;--c:${c}" title="${h(e.name)} ${s[0]}–${s[1]}${d.leave ? " · " + (d.leave.label || "άδεια") : ""}${d.departed ? " · μετά την αποχώρηση" : ""}${d.source === "temporary" ? " · προσωρινή αλλαγή" + (d.reason ? ": " + d.reason : "") : ""}">
        <span>${s[0]}–${s[1]}</span>${d.leave ? `<em>${h(d.leave.label || "άδεια")}</em>` : d.departed ? `<em>αποχώρηση</em>` : ""}</div>`;
    }).join("");
    const leaveNoShift = d.leave && !(d.segments || []).length ? `<div class="sc-note">${h(d.leave.label || "άδεια")}</div>` : "";
    return `<div class="sc-col"><button class="sc-ch" ${manage ? `data-emp="${h(e.code)}"` : "disabled"} style="--c:${c}" title="${manage ? "Αλλαγή προγράμματος" : ""}">
        <strong>${h(e.name)}</strong><span>${h(e.specialty || "")}${d.minutes ? ` · ${num2(d.minutes / 60)}ώ` : ""}${d.pending ? ` · ⏳ ${h(d.pending.label)}` : ""}${d.overlap ? " · ⚠" : ""}</span></button>
      <div class="sc-track" style="height:${H}px">${bars}${leaveNoShift}</div></div>`;
  };
  return `<div class="sc-wrap"><div class="sc-grid">
    <div class="sc-col sc-time"><div class="sc-ch"><strong>Ώρα</strong><span>${hours ? `${hours.opens}–${hours.closes}` : "χωρίς ωράριο"}</span></div>
      <div class="sc-track" style="height:${H}px">${slots.map((x, i) => `<div class="sc-t" style="top:${i * ROW}px">${x.slot}</div>`).join("")}</div></div>
    ${emps.map(col).join("")}
    <div class="sc-col sc-cnt"><div class="sc-ch"><strong>Παρόντες</strong><span>ανά μισάωρο</span></div>
      <div class="sc-track" style="height:${H}px">${slots.map((x, i) => `<div class="sc-c ${x.uncovered ? "bad" : ""} ${x.open === false ? "closed" : ""}" style="top:${i * ROW}px" title="${x.present ? x.present.length + " άτομα" : ""}${x.required != null ? ` · απαίτηση ${x.required}` : ""}">${x.count}${x.staffing === "under" ? ` <small>↓${x.required}</small>` : x.staffing === "over" ? ` <small>↑${x.required}</small>` : ""}</div>`).join("")}</div></div>
  </div></div>`;
}

// ── Επεξεργαστής διαστημάτων (έτοιμα ωράρια ή ελεύθερη ώρα, σπαστά) ──
function segEditor(id, segs, templates) {
  return `<div class="seg-ed" id="${id}">
    <div class="row-actions" style="margin-bottom:6px"><select class="tpl"><option value="">Έτοιμο ωράριο…</option>${templates.filter((t) => t.active).map((t) => `<option value='${h(JSON.stringify(t.segments))}'>${h(t.label)}</option>`).join("")}<option value="[]">Ρεπό / εκτός προγράμματος</option></select>
      <button type="button" class="btn sm add">+ διάστημα</button></div>
    <div class="rows">${(segs || []).map((s) => segRow(s)).join("")}</div></div>`;
}
const segRow = (s = ["", ""]) => `<div class="row-actions seg-row" style="flex-wrap:nowrap;margin-bottom:4px"><input type="time" step="300" value="${s[0]}" required><span>–</span><input type="time" step="300" value="${s[1]}" required><button type="button" class="btn sm ghost del" aria-label="Αφαίρεση">✕</button></div>`;
function bindSegEditor(root) {
  const rows = root.querySelector(".rows");
  const bindDel = () => rows.querySelectorAll(".del").forEach((b) => (b.onclick = () => b.closest(".seg-row").remove()));
  root.querySelector(".add").onclick = () => { rows.insertAdjacentHTML("beforeend", segRow()); bindDel(); };
  root.querySelector(".tpl").onchange = (e) => { if (e.target.value === "") return; rows.innerHTML = JSON.parse(e.target.value).map((s) => segRow(s)).join(""); bindDel(); e.target.value = ""; };
  bindDel();
}
const readSegs = (root) => [...root.querySelectorAll(".seg-row")].map((r) => [...r.querySelectorAll("input")].map((i) => i.value)).filter((x) => x[0] || x[1]);

async function employeeDialog(w, e, F, reload) {
  const [templates, patterns] = await Promise.all([S.api.shiftTemplates(), S.api.schedPatterns(e.code)]);
  const cur = patterns.find((p) => p.status === "active" && p.valid_from <= F.day && (!p.valid_to || p.valid_to >= F.day));
  const st = { mode: "temp" };
  const draw = () => {
    openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(F.store)} · ${h(e.specialty || "")}</div><h2>${h(e.name)}</h2></div><button class="icon-btn" data-close>✕</button></div>
      <div class="seg" role="radiogroup" style="margin-bottom:12px"><button type="button" data-m="temp" class="${st.mode === "temp" ? "on" : ""}">Προσωρινή αλλαγή</button><button type="button" data-m="perm" class="${st.mode === "perm" ? "on" : ""}">Σταθερό / μόνιμη αλλαγή</button></div>
      ${st.mode === "temp" ? `
        <p class="muted small">Ισχύει μόνο για τις ημερομηνίες που επιλέγετε· μετά επιστρέφει αυτόματα στο σταθερό πρόγραμμα.</p>
        <label>Ημερομηνίες</label><div class="chips">${w.days.map((d, i) => { const x = e.days[d] || {}; return `<label class="chip"><input type="checkbox" class="td" value="${d}" ${d === F.day ? "checked" : ""}> ${DOW_S[i]} ${d.slice(8)}/${d.slice(5, 7)} <span class="muted small">${segText(x.segments)}${x.source === "temporary" ? " (προσωρινή)" : ""}</span></label>`; }).join("")}</div>
        <label>Ωράριο για τις επιλεγμένες ημέρες</label>${segEditor("ed-t", (e.days[F.day] || {}).segments || [], templates)}
      ` : `
        <p class="muted small">Το σταθερό πρόγραμμα επαναλαμβάνεται κάθε εβδομάδα. Νέα ημερομηνία ισχύος = μόνιμη αλλαγή· το προηγούμενο κλείνει την προηγούμενη ημέρα.</p>
        <label>Ισχύει από</label><input type="date" id="pf-from" value="${F.week}" style="width:auto">
        ${cur ? `<p class="muted small">Τρέχον σταθερό από ${dmy(cur.valid_from)}${cur.valid_to ? ` έως ${dmy(cur.valid_to)}` : ""}.</p>` : `<p class="muted small">Δεν υπάρχει σταθερό πρόγραμμα.</p>`}
        ${DOW.map((n, i) => `<div class="pf-day"><strong>${n}</strong>${segEditor("ed-" + (i + 1), cur?.days?.[i + 1] || [], templates)}</div>`).join("")}
      `}
      <label>Αιτιολογία ${w.finalized ? "<span class='badge b-pending'>υποχρεωτική — οριστικοποιημένο πρόγραμμα</span>" : "<span class='muted'>(υποχρεωτική αν αγγίζει οριστικοποιημένη εβδομάδα)</span>"}</label>
      <input id="ed-reason" maxlength="300">
      <p id="ed-m" class="form-msg"></p>
      <div class="dlg-foot">${st.mode === "temp" ? `<button class="btn" id="ed-clear">Επαναφορά στο σταθερό</button>` : ""}<span class="spacer"></span><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="ed-ok">Αποθήκευση</button></div>`, {
      wide: true,
      onOpen() {
        $$("[data-m]").forEach((b) => (b.onclick = () => { st.mode = b.dataset.m; draw(); }));
        $$(".seg-ed").forEach(bindSegEditor);
        const reason = () => $("#ed-reason").value.trim();
        const days = () => $$(".td:checked").map((x) => x.value);
        $("#ed-ok").onclick = async () => {
          try {
            if (st.mode === "temp") {
              if (!days().length) throw new Error("Επιλέξτε ημερομηνίες.");
              await S.api.schedSetTemp(e.code, days(), readSegs($("#ed-t")), reason());
            } else {
              const d = {}; for (let i = 1; i <= 7; i++) d[i] = readSegs($("#ed-" + i));
              await S.api.schedSetPattern(e.code, $("#pf-from").value, d, reason());
            }
            closeDialog(); toast("Το πρόγραμμα αποθηκεύτηκε."); reload();
          } catch (err) { $("#ed-m").textContent = err.message; }
        };
        $("#ed-clear") && ($("#ed-clear").onclick = async () => {
          try { await S.api.schedClearTemp(e.code, days(), reason()); closeDialog(); toast("Επαναφορά στο σταθερό πρόγραμμα."); reload(); } catch (err) { $("#ed-m").textContent = err.message; }
        });
      },
    });
  };
  draw();
}

async function historyDialog(store, week) {
  const list = await S.api.schedHistory(store, addDays(week, -56), addDays(week, 62));
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(store)}</div><h2>Ιστορικό προγράμματος</h2></div><button class="icon-btn" data-close>✕</button></div>
    <div class="table-wrap" style="max-height:60vh"><table><thead><tr><th>Πότε / ποιος</th><th>Αλλαγή</th><th>Εργαζόμενος · ημερομηνίες</th><th>Προηγούμενο → Νέο</th><th>Αιτιολογία</th></tr></thead><tbody>
    ${list.map((c) => `<tr><td class="small">${athens(c.at)}<br>${h(c.actor)}</td><td class="small">${CHANGE_GR[c.change_type] || c.change_type}${c.after_finalize ? `<br><span class="badge b-pending">μετά την οριστικοποίηση</span>` : ""}</td>
      <td class="small">${h(c.employee_code || "—")}<br>${c.affected_from ? dmy(c.affected_from) : ""}${c.affected_to && c.affected_to !== c.affected_from ? " – " + dmy(c.affected_to) : ""}${c.effective_date ? `<br>ισχύς ${dmy(c.effective_date)}` : ""}</td>
      <td class="small">${describeChange(c)}</td><td class="small">${h(c.reason || "—")}</td></tr>`).join("") || `<tr><td colspan="5" class="muted">Καμία αλλαγή.</td></tr>`}
    </tbody></table></div><div class="dlg-foot"><button class="btn primary" data-close>Κλείσιμο</button></div>`, { wide: true });
}
function describeChange(c) {
  if (c.change_type === "temporary") return `${Object.entries(c.prev_value || {}).map(([d, s]) => `${dmy(d)}: ${segText(s)}`).join("<br>")} → ${segText(c.new_value?.segments)}`;
  if (c.change_type === "permanent") return `${c.prev_value ? weekText(c.prev_value) : "—"} → ${weekText(c.new_value)}`;
  if (c.change_type === "transfer") return `${h(c.prev_value?.store)} → ${h(c.new_value?.store)}`;
  return "";
}
const weekText = (d) => DOW_S.map((n, i) => `${n} ${segText(d?.[i + 1])}`).join(", ");

async function settingsDialog(store) {
  const [hours, templates] = await Promise.all([S.api.storeHours(store), S.api.shiftTemplates()]);
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(store)}</div><h2>Ωράρια λειτουργίας & έτοιμα ωράρια</h2></div><button class="icon-btn" data-close>✕</button></div>
    <h3>Ωράριο λειτουργίας ανά τμήμα</h3>
    <p class="muted small">Χρησιμοποιείται για την κόκκινη επισήμανση «κανένας διαθέσιμος». Κενό τμήμα = όλο το κατάστημα. Νέα γραμμή με νεότερη ημερομηνία ισχύος αντικαθιστά την παλιά από εκείνη την ημέρα.</p>
    <div class="table-wrap" style="max-height:220px"><table><thead><tr><th>Τμήμα</th><th>Ημέρα</th><th>Ώρες</th><th>Ισχύς από</th><th></th></tr></thead><tbody>
      ${hours.map((x) => `<tr><td>${h(x.specialty || "Όλο το κατάστημα")}</td><td>${DOW[x.weekday - 1]}</td><td>${x.opens.slice(0, 5)}–${x.closes.slice(0, 5)}</td><td>${dmy(x.valid_from)}</td><td><button class="btn sm ghost" data-delh="${x.id}">✕</button></td></tr>`).join("") || `<tr><td colspan="5" class="muted">Δεν έχει οριστεί ωράριο.</td></tr>`}
    </tbody></table></div>
    <div class="grid g4" style="margin-top:8px"><div><label>Τμήμα</label><select id="sh-spec"><option value="">Όλο το κατάστημα</option>${activeSpecialties().map((s) => `<option>${h(s)}</option>`).join("")}</select></div>
      <div><label>Ανοίγει</label><input type="time" id="sh-o" value="06:30"></div><div><label>Κλείνει</label><input type="time" id="sh-c" value="22:00"></div><div><label>Ισχύς από</label><input type="date" id="sh-f" value="${athensToday()}"></div></div>
    <div class="chips" style="margin-top:6px">${DOW.map((n, i) => `<label class="chip"><input type="checkbox" class="sh-d" value="${i + 1}" checked> ${DOW_S[i]}</label>`).join("")}</div>
    <button class="btn" id="sh-add" style="margin-top:8px">Προσθήκη ωραρίου</button>
    <h3 style="margin-top:18px">Έτοιμα ωράρια</h3>
    ${templates.map((t) => `<div class="list-item"><div class="grow"><strong>${h(t.label)}</strong> <span class="muted small">${segText(t.segments)}</span></div><button class="btn sm" data-tog="${t.id}">${t.active ? "Απόκρυψη" : "Εμφάνιση"}</button></div>`).join("")}
    <div class="row-actions" style="margin-top:8px"><input id="tp-l" placeholder="Ονομασία (π.χ. 07:00–15:00)" maxlength="60" style="max-width:240px">${segEditor("tp-ed", [["", ""]], [])}</div>
    <button class="btn" id="tp-add">Προσθήκη έτοιμου ωραρίου</button>
    <p id="sh-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn primary" data-close>Κλείσιμο</button></div>`, {
    wide: true,
    onOpen() {
      bindSegEditor($("#tp-ed"));
      const again = () => settingsDialog(store);
      $("#sh-add").onclick = async () => {
        try {
          const rows = $$(".sh-d:checked").map((x) => ({ store, specialty: $("#sh-spec").value || null, weekday: Number(x.value), opens: $("#sh-o").value, closes: $("#sh-c").value, valid_from: $("#sh-f").value }));
          if (!rows.length) throw new Error("Επιλέξτε ημέρες.");
          await S.api.addStoreHours(rows); toast("Αποθηκεύτηκε."); again();
        } catch (e) { $("#sh-m").textContent = e.message; }
      };
      $$("[data-delh]").forEach((b) => (b.onclick = async () => { try { await S.api.removeStoreHour(Number(b.dataset.delh)); again(); } catch (e) { $("#sh-m").textContent = e.message; } }));
      $$("[data-tog]").forEach((b) => (b.onclick = async () => { const t = templates.find((x) => x.id === Number(b.dataset.tog)); try { await S.api.saveShiftTemplate({ id: t.id, active: !t.active }); again(); } catch (e) { $("#sh-m").textContent = e.message; } }));
      $("#tp-add").onclick = async () => {
        try {
          const segs = readSegs($("#tp-ed"));
          if (!$("#tp-l").value.trim() || !segs.length) throw new Error("Συμπληρώστε ονομασία και ώρες.");
          await S.api.saveShiftTemplate({ label: $("#tp-l").value.trim(), segments: segs, sort: templates.length + 1 }); again();
        } catch (e) { $("#sh-m").textContent = e.message; }
      };
    },
  });
}
