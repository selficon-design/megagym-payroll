// Ρυθμίσεις επέκτασης: Πρότυπα κειμένων (με εκδόσεις), είδη άδειας, λόγοι απόρριψης, ειδικότητες, πεδίο εκπαιδευτών
import { S, can, invalidate, activeStores, activeSpecialties } from "./core.js";
import { $, $$, h, toast, openDialog, closeDialog, confirmBox } from "./util.js";
import { athens, renderTemplate, demoNotice } from "./hr-common.js";
import { KINDS } from "./stats-calc.js";

const view = () => $("#view");
const SAMPLE = { ονοματεπώνυμο: "Μαρία Παπαδοπούλου", κωδικός: "MG1001", κατάστημα: "Γλυφάδα", κατηγορία: "Αλλαγή βάρδιας, ρεπό ή προγράμματος", είδος_άδειας: "κανονική (ετήσια) άδεια",
  έναρξη: "01/12/2026", λήξη: "05/12/2026", ημέρες: "4", αιτιολογία: "Πλήρης στελέχωση λόγω εορτών", εναλλακτικό_διάστημα: "Προς συνεννόηση", στοιχεία: "βεβαίωση ιατρού",
  περίοδος: "των εορτών", ημερομηνία_περιστατικού: "28/10/2026" };

export async function templates() {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Πρότυπα κειμένων"));
  if (!can.templates()) return (view().innerHTML = `<div class="card empty">Τα πρότυπα τα επεξεργάζεται η Γενική Διευθύντρια.</div>`);
  const [tpls, lts, rrs] = await Promise.all([S.api.templates(), S.api.leaveTypes(), S.api.rejectReasons()]);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Ρυθμίσεις</div><h1>Πρότυπα κειμένων</h1>
    <p class="muted">Κάθε αλλαγή αποθηκεύεται ως νέα έκδοση και ισχύει για τις νέες καταχωρίσεις. Τα κείμενα αιτημάτων και αποφάσεων που έχουν ήδη αποθηκευτεί δεν αλλάζουν.</p></div></div>
  <div class="grid g2">${tpls.map((t) => `<div class="card"><div class="card-head"><h3>${h(t.label)}</h3><span class="muted small">έκδοση ${t.current?.version}</span></div>
      <p class="muted small">${h(t.description || "")}</p>
      ${t.variables.length ? `<div class="chips" style="margin:8px 0">${t.variables.map((v) => `<span class="chip">{${h(v)}}</span>`).join("")}</div>` : ""}
      <div class="statement small">${h(t.current?.body || "")}</div>
      <div class="row-actions" style="margin-top:10px"><button class="btn sm primary" data-edit="${t.key}">Επεξεργασία</button>${t.history.length > 1 ? `<button class="btn sm" data-hist="${t.key}">Εκδόσεις (${t.history.length})</button>` : ""}</div></div>`).join("")}</div>

  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Είδη άδειας</h3><button class="btn sm" id="lt-new">+ Νέο είδος</button></div>
    <div class="table-wrap"><table><thead><tr><th>Κωδικός</th><th>Περιγραφή (όπως μπαίνει στο κείμενο)</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
    ${lts.map((x) => `<tr><td class="num small">${h(x.code)}</td><td>${h(x.label)}</td><td><span class="badge ${x.active ? "b-signed" : "b-missing"}">${x.active ? "Ενεργό" : "Ανενεργό"}</span></td><td style="text-align:right"><button class="btn sm" data-lt="${x.code}">Επεξεργασία</button></td></tr>`).join("")}
    </tbody></table></div></div>

  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Λόγοι απόρριψης</h3><button class="btn sm" id="rr-new">+ Νέος λόγος</button></div>
    <p class="muted small" style="margin-bottom:10px">Σε ποια είδη άδειας εμφανίζεται κάθε λόγος. Οι αποφάσεις κρατούν τη διατύπωση που ίσχυε τότε. Η απόρριψη απαιτεί πάντα και συγκεκριμένη αιτιολογία.</p>
    <div class="table-wrap"><table><thead><tr><th>Λόγος</th><th>Είδη άδειας</th><th>Λοιπά αιτήματα</th><th>Κατάσταση</th><th></th></tr></thead><tbody>
    ${rrs.map((x) => `<tr><td>${h(x.label)}${x.template_key ? `<span class="sub">με πρότυπο αιτιολογίας</span>` : ""}</td><td class="small">${x.leave_types ? x.leave_types.map((c) => h(lts.find((l) => l.code === c)?.label || c)).join(", ") : "Όλα"}</td>
      <td>${x.for_other ? "Ναι" : "Όχι"}</td><td><span class="badge ${x.active ? "b-signed" : "b-missing"}">${x.active ? "Ενεργός" : "Ανενεργός"}</span></td><td style="text-align:right"><button class="btn sm" data-rr="${x.code}">Επεξεργασία</button></td></tr>`).join("")}
    </tbody></table></div></div>`;
  const reload = () => { invalidate(); templates(); };
  $$("[data-edit]").forEach((b) => (b.onclick = () => {
    const t = tpls.find((x) => x.key === b.dataset.edit);
    openDialog(`<div class="dlg-head"><div><div class="eyebrow">Νέα έκδοση ${t.current.version + 1}</div><h2>${h(t.label)}</h2></div><button class="icon-btn" data-close>✕</button></div>
      ${t.variables.length ? `<p class="muted small">Μεταβλητές: ${t.variables.map((v) => `<button type="button" class="chip" data-var="${h(v)}">{${h(v)}}</button>`).join(" ")}</p>` : ""}
      <textarea id="te-b" rows="9" maxlength="8000">${h(t.current.body)}</textarea>
      <label>Προεπισκόπηση με εικονικά στοιχεία</label><div class="statement small" id="te-p"></div><p id="te-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="te-ok">Αποθήκευση νέας έκδοσης</button></div>`, {
      wide: true,
      onOpen() {
        const prev = () => ($("#te-p").textContent = renderTemplate($("#te-b").value, SAMPLE));
        $("#te-b").oninput = prev; prev();
        $$("[data-var]").forEach((c) => (c.onclick = () => { const ta = $("#te-b"); const p = ta.selectionStart; ta.setRangeText(`{${c.dataset.var}}`, p, ta.selectionEnd, "end"); ta.focus(); prev(); }));
        $("#te-ok").onclick = async () => {
          const unknown = [...$("#te-b").value.matchAll(/\{([^{}\s]+)\}/g)].map((m) => m[1]).filter((v) => !t.variables.includes(v));
          if (unknown.length && !(await confirmBox("Άγνωστες μεταβλητές", `Οι μεταβλητές ${unknown.map((u) => `{${u}}`).join(", ")} δεν συμπληρώνονται αυτόματα σε αυτό το πρότυπο. Συνέχεια;`, { ok: "Αποθήκευση" }))) return;
          try { await S.api.templateSave(t.key, $("#te-b").value); closeDialog(); toast("Αποθηκεύτηκε νέα έκδοση."); reload(); } catch (e) { $("#te-m").textContent = e.message; }
        };
      },
    });
  }));
  $$("[data-hist]").forEach((b) => (b.onclick = () => {
    const t = tpls.find((x) => x.key === b.dataset.hist);
    openDialog(`<div class="dlg-head"><h2>${h(t.label)} — εκδόσεις</h2><button class="icon-btn" data-close>✕</button></div>
      ${t.history.map((v) => `<div style="margin-top:14px"><strong>Έκδοση ${v.version}</strong> <span class="muted small">${h(v.created_by)} · ${athens(v.created_at)}${v.version === t.current.version ? " · τρέχουσα" : ""}</span><div class="statement small">${h(v.body)}</div></div>`).join("")}
      <div class="dlg-foot"><button class="btn primary" data-close>Κλείσιμο</button></div>`, { wide: true });
  }));
  const ltDialog = (x) => {
    const isNew = !x; x ??= { code: "", label: "", sort: lts.length + 1, active: true };
    openDialog(`<div class="dlg-head"><h2>${isNew ? "Νέο είδος άδειας" : "Είδος άδειας"}</h2><button class="icon-btn" data-close>✕</button></div>
      <div class="grid g2"><div><label>Κωδικός (λατινικά, π.χ. annual)</label><input id="lt-c" value="${h(x.code)}" ${isNew ? "" : "readonly"} pattern="[a-z_]{2,30}"></div>
      <div><label>Κατάσταση</label><select id="lt-a"><option value="1" ${x.active ? "selected" : ""}>Ενεργό</option><option value="0" ${x.active ? "" : "selected"}>Ανενεργό</option></select></div></div>
      <label>Περιγραφή (π.χ. «κανονική (ετήσια) άδεια»)</label><input id="lt-l" maxlength="80" value="${h(x.label)}"><p id="lt-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="lt-ok">Αποθήκευση</button></div>`, {
      onOpen() { $("#lt-ok").onclick = async () => { try { await S.api.saveLeaveType({ code: $("#lt-c").value.trim(), label: $("#lt-l").value.trim(), sort: x.sort, active: $("#lt-a").value === "1" }, isNew); closeDialog(); reload(); } catch (e) { $("#lt-m").textContent = e.message; } }; },
    });
  };
  $("#lt-new").onclick = () => ltDialog(null);
  $$("[data-lt]").forEach((b) => (b.onclick = () => ltDialog(lts.find((x) => x.code === b.dataset.lt))));
  const rrDialog = (x) => {
    const isNew = !x; x ??= { code: "", label: "", leave_types: null, for_other: true, template_key: null, sort: rrs.length + 1, active: true };
    openDialog(`<div class="dlg-head"><h2>${isNew ? "Νέος λόγος απόρριψης" : "Λόγος απόρριψης"}</h2><button class="icon-btn" data-close>✕</button></div>
      <div class="grid g2"><div><label>Κωδικός (λατινικά)</label><input id="rr-c" value="${h(x.code)}" ${isNew ? "" : "readonly"}></div>
      <div><label>Κατάσταση</label><select id="rr-a"><option value="1" ${x.active ? "selected" : ""}>Ενεργός</option><option value="0" ${x.active ? "" : "selected"}>Ανενεργός</option></select></div></div>
      <label>Διατύπωση</label><input id="rr-l" maxlength="200" value="${h(x.label)}">
      <label>Είδη άδειας</label><div class="chips"><label class="chip ${!x.leave_types ? "on" : ""}" style="margin:0"><input type="checkbox" id="rr-all" ${!x.leave_types ? "checked" : ""} hidden>Όλα</label>
        ${lts.map((l) => `<label class="chip ${x.leave_types?.includes(l.code) ? "on" : ""}" style="margin:0"><input type="checkbox" class="rr-lt" value="${l.code}" ${x.leave_types?.includes(l.code) ? "checked" : ""} hidden>${h(l.label)}</label>`).join("")}</div>
      <label class="check" style="margin-top:12px"><input type="checkbox" id="rr-o" ${x.for_other ? "checked" : ""}> Εμφανίζεται και σε αιτήματα εκτός αδειών</label>
      <p id="rr-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="rr-ok">Αποθήκευση</button></div>`, {
      onOpen() {
        $$("#dlg .chips input").forEach((i) => (i.onchange = () => { if (i.id === "rr-all" && i.checked) $$(".rr-lt").forEach((c) => (c.checked = false)); if (i.classList.contains("rr-lt") && i.checked) $("#rr-all").checked = false; $$("#dlg .chips input").forEach((c) => c.parentElement.classList.toggle("on", c.checked)); }));
        $("#rr-ok").onclick = async () => {
          const sel = $$(".rr-lt:checked").map((i) => i.value);
          try { await S.api.saveRejectReason({ code: $("#rr-c").value.trim(), label: $("#rr-l").value.trim(), leave_types: $("#rr-all").checked || !sel.length ? null : sel, for_other: $("#rr-o").checked, template_key: x.template_key, sort: x.sort, active: $("#rr-a").value === "1" }, isNew); closeDialog(); reload(); }
          catch (e) { $("#rr-m").textContent = e.message; }
        };
      },
    });
  };
  $("#rr-new").onclick = () => rrDialog(null);
  $$("[data-rr]").forEach((b) => (b.onclick = () => rrDialog(rrs.find((x) => x.code === b.dataset.rr))));
}

/** Ειδικότητες (μέσα στις Ρυθμίσεις) */
export function specialtiesBlock() {
  if (S.api.mode === "demo") return "";
  return `<div class="card" style="margin-top:16px"><div class="card-head"><h3>Ειδικότητες</h3></div>
    <p class="muted small">Ποια πεδία ημερήσιων στατιστικών καταχωρίζονται για κάθε ειδικότητα.</p>
    ${(S.lists.specialties || []).map((x) => `<div class="list-item"><div class="grow"><strong>${h(x.name)}</strong> <span class="muted small">${x.stat_kind ? "Στατιστικά: " + KINDS[x.stat_kind].label : "Χωρίς στατιστικά"}</span></div>
      <span class="badge ${x.active ? "b-signed" : "b-missing"}">${x.active ? "Ενεργή" : "Ανενεργή"}</span><button class="btn sm" data-sp="${h(x.name)}">${x.active ? "Απενεργοποίηση" : "Ενεργοποίηση"}</button></div>`).join("")}
    <form class="row-actions" style="margin-top:14px;flex-wrap:nowrap" id="sp-add"><input placeholder="Νέα ειδικότητα" required minlength="2" maxlength="80">
      <select style="width:auto"><option value="">Χωρίς στατιστικά</option>${Object.entries(KINDS).map(([k, v]) => `<option value="${k}">Στατιστικά ${v.label}</option>`).join("")}</select><button class="btn">Προσθήκη</button></form></div>`;
}
export function bindSpecialties(reload) {
  $$("[data-sp]").forEach((b) => (b.onclick = async () => {
    const x = S.lists.specialties.find((s) => s.name === b.dataset.sp);
    try { await S.api.saveSpecialty({ name: x.name, active: !x.active }, false); await reload(); } catch (e) { toast(e.message, true); }
  }));
  $("#sp-add") && ($("#sp-add").onsubmit = async (e) => {
    e.preventDefault();
    const [inp, sel] = [$("#sp-add input"), $("#sp-add select")];
    try { await S.api.saveSpecialty({ name: inp.value.trim(), stat_kind: sel.value || null, sort: S.lists.specialties.length + 1, active: true }, true); toast("Προστέθηκε."); await reload(); } catch (err) { toast(err.message, true); }
  });
}

/** Πεδίο ευθύνης εκπαιδευτή (μέσα στη Διαχείριση χρηστών) */
export async function trainerScopeDialog(u) {
  const all = await S.api.trainerScopes();
  const mine = all.filter((x) => x.email === u.email);
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">Εκπαιδευτής</div><h2>Πεδίο ευθύνης: ${h(u.name)}</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Ο εκπαιδευτής ανοίγει αξιολογήσεις ΜΟΝΟ για εργαζόμενους που ταιριάζουν σε κάποια από τις παρακάτω γραμμές. Δεν έχει πρόσβαση σε μισθοδοσία, άδειες, αναφορές ή διαχείριση χρηστών.</p>
    ${mine.length ? mine.map((x) => `<div class="list-item"><div class="grow">${h(x.store || "Όλα τα καταστήματα")} · ${h(x.specialty || "Όλες οι ειδικότητες")}</div><button class="btn sm ghost" data-rm="${x.id}">Αφαίρεση</button></div>`).join("") : `<div class="note warn" style="margin-top:10px">Δεν έχει οριστεί πεδίο· ο εκπαιδευτής δεν βλέπει κανέναν εργαζόμενο.</div>`}
    <div class="grid g2" style="margin-top:14px"><div><label>Κατάστημα</label><select id="tsc-s"><option value="">Όλα τα καταστήματα</option>${activeStores().map((s) => `<option>${h(s)}</option>`).join("")}</select></div>
      <div><label>Ειδικότητα</label><select id="tsc-p"><option value="">Όλες οι ειδικότητες</option>${activeSpecialties().map((s) => `<option>${h(s)}</option>`).join("")}</select></div></div>
    <p id="tsc-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Κλείσιμο</button><button class="btn primary" id="tsc-add">Προσθήκη γραμμής</button></div>`, {
    onOpen() {
      $("#tsc-add").onclick = async () => { try { await S.api.addTrainerScope({ email: u.email, store: $("#tsc-s").value || null, specialty: $("#tsc-p").value || null }); trainerScopeDialog(u); } catch (e) { $("#tsc-m").textContent = e.message; } };
      $$("[data-rm]").forEach((b) => (b.onclick = async () => { try { await S.api.removeTrainerScope(Number(b.dataset.rm)); trainerScopeDialog(u); } catch (e) { toast(e.message, true); } }));
    },
  });
}
