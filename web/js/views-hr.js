// Αιτήματα & Αναφορές Προσωπικού: πίνακας ελέγχου, φίλτρα, δημιουργία (Α/Β), καρτέλα αιτήματος, αποφάσεις
import { S, can, role, getEmployees, visibleStores, invalidate } from "./core.js";
import { $, $$, h, dmy, toast, openDialog, closeDialog, confirmBox, norm, downloadXlsx, saveBlob } from "./util.js";
import {
  CATEGORIES, EMPLOYEE_CATS, MANAGER_CATS, flowOf, FLOW_NOTE, REQ_STATUS, reqBadge, who, renderTemplate, leaveVars,
  calendarDays, athens, athensToday, fileToPayload, base64ToBlob, reasonsFor, demoNotice, daysWord,
} from "./hr-common.js";
import { enterFill } from "./fill-launch.js";

const view = () => $("#view");

export async function hrRefs() {
  return (S.cache.hrRefs ??= Promise.all([S.api.templates(), S.api.leaveTypes(), S.api.rejectReasons()])
    .then(([t, lt, rr]) => ({ templates: t, tpl: Object.fromEntries(t.map((x) => [x.key, x.current])), leaveTypes: lt, reasons: rr }))
    .catch((e) => { delete S.cache.hrRefs; throw e; }));
}

// ═══════════════════════ Πίνακας & λίστα αιτημάτων ═══════════════════════
function buckets(list) {
  const r = role(), me = S.me.email;
  const mine = list.filter((x) => {
    const f = flowOf(x.category);
    if (r === "owner") return x.status === "awaiting_gm" || (["leave", "generic"].includes(f) && ["submitted", "under_review"].includes(x.status)) || (Number(x.leave_excess) > 0 && ["submitted", "under_review"].includes(x.status));
    if (r === "hr") return ["submitted", "under_review"].includes(x.status) && (!x.assignee || x.assignee === me);
    if (r === "manager") return x.status === "needs_info" || (x.status === "draft" && x.created_by === me) || (["approved", "rejected"].includes(x.status) && !x.notified_at && f !== "warning")
      || (x.status === "approved" && x.notified_at && ["leave", "generic", "gm"].includes(f) && (!x.impl_claimed_by || x.impl_claimed_by === me));
    return false;
  });
  return {
    mine,
    hr: list.filter((x) => ["submitted", "under_review"].includes(x.status)),
    impl: list.filter((x) => x.status === "approved"),
  };
}

export async function requests(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αιτήματα & Αναφορές"));
  if (!can.requests()) return (view().innerHTML = `<div class="card empty">Δεν έχετε πρόσβαση στα αιτήματα.</div>`);
  const F = (S.filters.req ??= { bucket: "", q: "", store: "", cat: "", status: "open", from: "", to: "", assignee: "" });
  if (params.get("bucket") !== null) F.bucket = params.get("bucket") || "";
  const all0 = await S.api.requests();
  const all = all0.filter((x) => x.status !== "draft" || x.created_by === S.me.email);
  const B = buckets(all);
  const base = F.bucket ? B[F.bucket] : all;
  const OPEN = ["submitted", "under_review", "needs_info", "awaiting_gm", "approved"];
  const list = base.filter((x) =>
    (!F.q || norm(`${x.employee_name} ${x.employee_code} ${x.ref}`).includes(norm(F.q))) &&
    (!F.store || x.store === F.store) && (!F.cat || x.category === F.cat) &&
    (F.status === "all" || (F.status === "open" ? OPEN.includes(x.status) : x.status === F.status) || F.bucket) &&
    (!F.from || (x.submitted_at || x.created_at).slice(0, 10) >= F.from) && (!F.to || (x.submitted_at || x.created_at).slice(0, 10) <= F.to) &&
    (!F.assignee || (F.assignee === "-" ? !x.assignee : x.assignee === F.assignee)));
  const assignees = [...new Set(all.map((x) => x.assignee).filter(Boolean))];
  const card = (k, label, hint, n, cls) => `<a class="card kpi ${cls} ${F.bucket === k ? "sel" : ""}" href="#/requests?bucket=${F.bucket === k ? "" : k}" style="text-decoration:none"><div class="label">${label}</div><div class="value num">${n}</div><div class="hint">${hint}</div></a>`;

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Προσωπικό</div><h1>Αιτήματα & Αναφορές</h1>
    <p class="muted">${role() === "manager" ? `Κατάστημα ${h(S.me.store)}. ` : ""}Οι εργαζόμενοι δεν έχουν λογαριασμό· τα αιτήματα καταχωρίζονται μέσω του manager.</p></div>
    <div class="row-actions">
      <button class="btn" id="rq-export">⇩ Excel</button>
      ${can.createRequests() ? `<a class="btn" href="#/request-new?kind=manager">+ Αναφορά manager</a><a class="btn primary" href="#/request-new?kind=employee">+ Αίτημα εργαζομένου</a>` : ""}
    </div></div>
  <div class="grid g3">
    ${card("mine", "Χρειάζονται ενέργειά μου", role() === "owner" ? "αποφάσεις ΓΔ, υπερβάσεις υπολοίπου, άδειες/λοιπά" : role() === "hr" ? "νέα ή ανατεθειμένα σε εμένα" : "διευκρινίσεις, πρόχειρα, ενημέρωση εργαζομένου, υλοποίηση", B.mine.length, "warn")}
    ${card("hr", "Εκκρεμούν στο HR", "υποβλήθηκαν ή σε εξέταση", B.hr.length, "")}
    ${card("impl", "Εγκρίθηκαν — αναμένεται υλοποίηση", "η έγκριση δεν είναι υλοποίηση", B.impl.length, "ok")}
  </div>
  <div class="card" style="margin-top:16px">
    ${F.bucket ? `<div class="note" style="margin-bottom:12px">Εμφανίζεται: <strong>${{ mine: "Χρειάζονται ενέργειά μου", hr: "Εκκρεμούν στο HR", impl: "Εγκρίθηκαν — αναμένεται υλοποίηση" }[F.bucket]}</strong> · <a href="#/requests?bucket=">όλα τα αιτήματα</a></div>` : ""}
    <div class="toolbar">
      <input type="search" id="rq-q" placeholder="Εργαζόμενος, κωδικός ή αριθμός" value="${h(F.q)}">
      ${role() === "manager" ? "" : `<select id="rq-store"><option value="">Όλα τα καταστήματα</option>${visibleStores().map((s) => `<option ${s === F.store ? "selected" : ""}>${h(s)}</option>`).join("")}</select>`}
      <select id="rq-cat"><option value="">Όλες οι κατηγορίες</option>${Object.entries(CATEGORIES).map(([k, v]) => `<option value="${k}" ${k === F.cat ? "selected" : ""}>${h(v)}</option>`).join("")}</select>
      <select id="rq-status" ${F.bucket ? "disabled" : ""}><option value="open">Ανοιχτά</option><option value="all">Όλες οι καταστάσεις</option>${Object.entries(REQ_STATUS).map(([k, v]) => `<option value="${k}">${v.label}</option>`).join("")}</select>
      ${can.decide() ? `<select id="rq-assignee"><option value="">Κάθε υπεύθυνος</option><option value="-">Χωρίς υπεύθυνο</option>${assignees.map((a) => `<option ${a === F.assignee ? "selected" : ""}>${h(a)}</option>`).join("")}</select>` : ""}
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Από <input type="date" id="rq-from" value="${h(F.from)}" style="width:auto"></label>
      <label class="small muted" style="margin:0;display:flex;gap:6px;align-items:center">Έως <input type="date" id="rq-to" value="${h(F.to)}" style="width:auto"></label>
    </div>
    ${list.length ? `<div class="table-wrap"><table class="stack"><thead><tr><th>Αριθμός</th><th>Εργαζόμενος</th><th>Κατηγορία</th><th>Κατάσταση</th><th>Υποβολή</th><th>Υπεύθυνος</th></tr></thead><tbody>
      ${list.map((x) => `<tr class="click" data-id="${h(x.id)}"><td><strong class="num">${h(x.ref)}</strong><span class="sub">${x.process === "manager" ? "Αναφορά manager" : "Αίτημα εργαζομένου"}</span></td>
        <td><strong>${h(x.employee_name)}</strong><span class="sub">${h(x.employee_code)} · ${h(x.store)}</span></td>
        <td data-l="Κατηγορία">${h(CATEGORIES[x.category])}${x.category === "leave" && x.start_date ? `<span class="sub">${dmy(x.start_date)} – ${dmy(x.end_date)} · ${daysWord(x.days_requested)} ημ.</span>` : ""}</td>
        <td>${reqBadge(x.status)}${x.status === "approved" && x.notified_at ? `<span class="sub">ενημερώθηκε${x.impl_claimed_by ? " · σε υλοποίηση" : ""}</span>` : ""}${Number(x.leave_excess) > 0 && !["approved", "completed", "rejected"].includes(x.status) ? `<span class="sub"><span class="badge b-voided">υπέρβαση ${String(x.leave_excess).replace(".", ",")}</span></span>` : ""}</td>
        <td data-l="Υποβολή" class="small">${x.submitted_at ? athens(x.submitted_at) : "—"}</td><td data-l="Υπεύθυνος" class="small">${h(x.assignee || "—")}</td></tr>`).join("")}
      </tbody></table></div>` : `<div class="empty"><div class="big">✉︎</div>Δεν βρέθηκαν αιτήματα με αυτά τα φίλτρα.</div>`}
  </div>`;
  $("#rq-status").value = F.status;
  const re = () => requests(new URLSearchParams());
  $("#rq-q").oninput = (e) => { F.q = e.target.value; re().then(() => { const i = $("#rq-q"); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }); };
  for (const [id, k] of [["rq-store", "store"], ["rq-cat", "cat"], ["rq-status", "status"], ["rq-assignee", "assignee"], ["rq-from", "from"], ["rq-to", "to"]]) {
    $("#" + id) && ($("#" + id).onchange = (e) => { F[k] = e.target.value; re(); });
  }
  $$("tr.click").forEach((tr) => (tr.onclick = () => (location.hash = `#/request?id=${tr.dataset.id}`)));
  $("#rq-export").onclick = () => downloadXlsx("Αιτήματα.xlsx", { "Αιτήματα": [["Αριθμός", "Διαδικασία", "Κωδικός", "Εργαζόμενος", "Κατάστημα", "Κατηγορία", "Κατάσταση", "Έναρξη", "Λήξη", "Ημέρες", "Υποβλήθηκε", "Υπέβαλε", "Υπεύθυνος", "Ενημέρωση εργαζομένου"],
    ...list.map((x) => [x.ref, x.process === "manager" ? "Αναφορά manager" : "Αίτημα εργαζομένου", x.employee_code, x.employee_name, x.store, CATEGORIES[x.category], REQ_STATUS[x.status].label, dmy(x.start_date), dmy(x.end_date), x.days_requested ?? "", x.submitted_at ? athens(x.submitted_at) : "", x.submitted_by || "", x.assignee || "", x.notified_at ? athens(x.notified_at) : ""])] });
}

// ═══════════════════════ Νέο αίτημα / επεξεργασία προχείρου ═══════════════════════
export async function requestNew(params, existing = null) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αιτήματα & Αναφορές"));
  if (!can.createRequests()) return (view().innerHTML = `<div class="card empty">Δεν έχετε δικαίωμα καταχώρισης αιτημάτων.</div>`);
  const kind = existing ? existing.process : params.get("kind") === "manager" ? "manager" : "employee";
  const origId = existing?.original_request_id || (params.get("kind") === "change" ? params.get("orig") : null);
  const [emps, R, orig] = await Promise.all([getEmployees(), hrRefs(), origId ? S.api.request(origId) : null]);
  const active = emps.filter((e) => e.status === "Ενεργός");
  const st = { code: existing?.employee_code || orig?.employee_code || params.get("code") || "", cat: existing?.category || (orig ? "leave_change" : kind === "manager" ? "negative_review" : "leave"),
    mode: existing?.entry_mode || "manager_record", bodyEdited: !!existing?.body, files: [] };
  const v = (k) => existing?.[k] ?? "";
  const d = (k) => existing?.details?.[k] ?? "";

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${kind === "manager" ? "Διαδικασία Β · Αναφορά ή αίτημα manager" : "Διαδικασία Α · Αίτημα εργαζομένου μέσω manager"}</div>
    <h1>${existing ? `Πρόχειρο ${h(existing.ref)}` : kind === "manager" ? "Νέα αναφορά manager" : "Νέο αίτημα εργαζομένου"}</h1></div>
    <a class="btn" href="${existing ? `#/request?id=${existing.id}` : "#/requests"}">Άκυρο</a></div>
  <form id="rf" class="card" style="max-width:860px">
    <div class="grid g2">
      <div><label>Εργαζόμενος</label><select id="rf-emp" ${existing || orig ? "disabled" : ""} required><option value="">— επιλέξτε —</option>
        ${active.map((e) => `<option value="${h(e.code)}" ${e.code === st.code ? "selected" : ""}>${h(e.last)} ${h(e.first)} · ${h(e.code)}${role() !== "manager" ? " · " + h(e.store) : ""}</option>`).join("")}</select></div>
      <div><label>Κατηγορία</label><select id="rf-cat" ${existing || orig ? "disabled" : ""}>${(orig ? ["leave_change"] : kind === "manager" ? MANAGER_CATS : EMPLOYEE_CATS).map((c) => `<option value="${c}" ${c === st.cat ? "selected" : ""}>${h(CATEGORIES[c])}</option>`).join("")}</select></div>
    </div>
    <div id="rf-emp-info" class="muted small" style="margin-top:8px"></div>
    ${kind === "employee" && !existing && !orig ? `<label>Ποιος συμπληρώνει το κείμενο;</label>
      <div class="chips" id="rf-mode">
        <button type="button" class="chip" data-mode="manager_record">Καταγραφή από manager</button>
        <button type="button" class="chip" data-mode="employee_fill">Συμπλήρωση από εργαζόμενο</button>
      </div>` : ""}
    <div id="rf-flow" class="note" style="margin-top:14px"></div>
    <div id="rf-fields"></div>
    <p id="rf-msg" class="form-msg"></p>
    <div class="dlg-foot" id="rf-actions"></div>
  </form>`;

  const empOf = () => active.find((e) => e.code === st.code) || (existing && { code: existing.employee_code, first: existing.employee_name, last: "", store: existing.store, company: existing.company });
  const leaveField = () => {
    const lt = $("#rf-lt")?.value, a = $("#rf-start")?.value, b = $("#rf-end")?.value;
    const label = R.leaveTypes.find((x) => x.code === lt)?.label || "";
    const cal = calendarDays(a, b);
    $("#rf-cal") && ($("#rf-cal").textContent = cal ? `Ημερολογιακές ημέρες διαστήματος: ${cal}. Δεν ταυτίζονται απαραίτητα με τις ημέρες άδειας.` : "");
    if (!st.bodyEdited && $("#rf-body") && st.cat === "leave") {
      $("#rf-body").value = renderTemplate(R.tpl.leave_request_body?.body, { είδος_άδειας: label, έναρξη: dmy(a), λήξη: dmy(b), ημέρες: daysWord($("#rf-days").value), ονοματεπώνυμο: empOf()?.first ? `${empOf().first} ${empOf().last}` : "" });
    }
    clearTimeout(st.pt); st.pt = setTimeout(() => leavePreviewBox($("#rf-prev"), st.code, a, b, lt || orig?.leave_type, existing?.id), 350);
  };
  const fileBox = `<label>Συνημμένα / δικαιολογητικά (προαιρετικά · PDF ή εικόνες έως 4 MB)</label><input type="file" id="rf-files" multiple accept=".pdf,.jpg,.jpeg,.png,.webp,.heic">
    ${existing?.attachments?.length ? `<p class="muted small" style="margin-top:6px">Ήδη: ${existing.attachments.map((a) => h(a.filename)).join(", ")}</p>` : ""}`;

  function drawFields() {
    const flow = flowOf(st.cat);
    $("#rf-flow").innerHTML = `<strong>${h(CATEGORIES[st.cat])}:</strong> ${h(FLOW_NOTE[flow])}`;
    $$("#rf-mode .chip").forEach((c) => c.classList.toggle("on", c.dataset.mode === st.mode));
    const e = empOf();
    $("#rf-emp-info").innerHTML = e ? `Κωδικός <strong>${h(e.code)}</strong> · ${h(e.store)} · ${h(e.company)}${e.specialty ? " · " + h(e.specialty) : ""}` : "";
    let html = "";
    if (kind === "manager") {
      html = `<div class="grid g2"><div><label>Ημερομηνία περιστατικού</label><input type="date" id="rf-incident" max="${athensToday()}" value="${h(v("incident_date"))}" required></div></div>
        <label>Περιγραφή</label><textarea id="rf-desc" maxlength="4000" required>${h(d("description"))}</textarea>
        <label>Συγκεκριμένα παραδείγματα</label><textarea id="rf-ex" maxlength="4000" required>${h(d("examples"))}</textarea>
        <label>Προηγούμενη συζήτηση με τον εργαζόμενο (πότε, τι ειπώθηκε· ή «Όχι»)</label><textarea id="rf-prior" maxlength="4000" rows="2" required>${h(d("prior_discussion"))}</textarea>
        <label>Προτεινόμενη ενέργεια</label><textarea id="rf-prop" maxlength="4000" rows="2" required>${h(d("proposed_action"))}</textarea>${fileBox}`;
    } else if (st.mode === "employee_fill") {
      html = `<div class="note warn" style="margin-top:14px">Ο εργαζόμενος θα συμπληρώσει ο ίδιος το αίτημα σε απομονωμένη οθόνη αυτής της συσκευής, χωρίς πρόσβαση σε άλλες καρτέλες ή δεδομένα. Μετά θα το ελέγξετε και θα το υποβάλετε εσείς.</div>
        ${st.cat === "leave" ? `<label>Εισήγηση manager για την κάλυψη του προγράμματος (δεν τη βλέπει ο εργαζόμενος)</label><textarea id="rf-mnote" maxlength="4000" rows="2">${h(v("manager_note"))}</textarea>` :
          `<label>Σημείωση manager (δεν τη βλέπει ο εργαζόμενος)</label><textarea id="rf-mnote" maxlength="4000" rows="2">${h(v("manager_note"))}</textarea>`}`;
    } else if (st.cat === "leave") {
      html = `<div class="grid g2">
          <div><label>Είδος άδειας</label><select id="rf-lt" required><option value="">— επιλέξτε —</option>${R.leaveTypes.filter((x) => x.active).map((x) => `<option value="${x.code}" ${x.code === v("leave_type") ? "selected" : ""}>${h(x.label)}</option>`).join("")}</select></div>
          <div><label>Αριθμός αιτούμενων ημερών άδειας</label><input id="rf-days" inputmode="decimal" value="${h(v("days_requested"))}" required></div>
          <div><label>Ημερομηνία έναρξης</label><input type="date" id="rf-start" value="${h(v("start_date"))}" required></div>
          <div><label>Ημερομηνία λήξης (συμπεριλαμβάνεται)</label><input type="date" id="rf-end" value="${h(v("end_date"))}" required></div>
        </div>
        <p id="rf-cal" class="muted small" style="margin-top:8px"></p>
        <div id="rf-prev"></div>
        <div class="statement small" style="margin-top:10px">${h(R.tpl.leave_request_help?.body || "")}</div>
        <label>Κείμενο αίτησης</label><textarea id="rf-body" rows="4" maxlength="8000" required>${h(v("body"))}</textarea>
        <label>Παρατηρήσεις (προαιρετικά)</label><textarea id="rf-notes" rows="2" maxlength="4000">${h(d("notes"))}</textarea>
        <label>Εισήγηση manager για την κάλυψη του προγράμματος (χωριστά από το αίτημα)</label><textarea id="rf-mnote" rows="2" maxlength="4000">${h(v("manager_note"))}</textarea>
        ${fileBox}`;
    } else if (st.cat === "leave_change") {
      html = `<div class="note" style="margin-top:12px">Αρχική άδεια <a href="#/request?id=${h(orig?.id)}"><strong>${h(orig?.ref || "")}</strong></a>: ${h(orig?.leave_type_label || "")} · ${dmy(orig?.start_date)} – ${dmy(orig?.end_date)}.
          Μέχρι να εγκριθεί η αλλαγή ισχύει η αρχική άδεια. Με την έγκριση ενημερώνονται ενιαία ημέρες, υπόλοιπο, ημερολόγιο και πρόγραμμα.</div>
        <div class="grid g2"><div><label>Νέα έναρξη</label><input type="date" id="rf-start" value="${h(v("start_date"))}" required></div>
          <div><label>Νέα λήξη (συμπεριλαμβάνεται)</label><input type="date" id="rf-end" value="${h(v("end_date"))}" required></div></div>
        <p id="rf-cal" class="muted small" style="margin-top:8px"></p><div id="rf-prev"></div>
        <label>Αιτιολογία / κείμενο αιτήματος αλλαγής</label><textarea id="rf-body" rows="3" maxlength="8000" required>${h(v("body"))}</textarea>
        <label>Εισήγηση manager για το πρόγραμμα</label><textarea id="rf-mnote" rows="2" maxlength="4000">${h(v("manager_note"))}</textarea>`;
    } else {
      html = `<label>Θέμα</label><input id="rf-subject" maxlength="200" value="${h(d("subject"))}">
        <label>Κείμενο αιτήματος (όπως το διατύπωσε ο εργαζόμενος)</label><textarea id="rf-body" rows="5" maxlength="8000" required>${h(v("body"))}</textarea>
        <label>Σημείωση / εισήγηση manager (χωριστά)</label><textarea id="rf-mnote" rows="2" maxlength="4000">${h(v("manager_note"))}</textarea>${fileBox}`;
    }
    $("#rf-fields").innerHTML = html;
    $("#rf-actions").innerHTML = st.mode === "employee_fill" && kind === "employee" && !existing
      ? `<button class="btn primary" id="rf-fill">Άνοιγμα φόρμας εργαζομένου →</button>`
      : `<button class="btn" id="rf-save">Αποθήκευση προχείρου</button><button class="btn primary" id="rf-submit">Υποβολή</button>`;
    if ((st.cat === "leave" || st.cat === "leave_change") && st.mode === "manager_record") {
      ["rf-lt", "rf-start", "rf-end", "rf-days"].forEach((id) => $("#" + id) && ($("#" + id).oninput = leaveField));
      $("#rf-body").oninput = () => (st.bodyEdited = true);
      leaveField();
    }
    $("#rf-files") && ($("#rf-files").onchange = (ev) => (st.files = [...ev.target.files]));
    bindActions();
  }

  function collect() {
    const p = { category: st.cat, employee_code: st.code, entry_mode: kind === "employee" ? st.mode : undefined };
    const val = (id) => $("#" + id)?.value?.trim();
    if (kind === "manager") {
      p.incident_date = val("rf-incident");
      p.details = { description: val("rf-desc"), examples: val("rf-ex"), prior_discussion: val("rf-prior"), proposed_action: val("rf-prop") };
    } else {
      if ($("#rf-mnote")) p.manager_note = val("rf-mnote");
      if (st.mode === "manager_record") {
        p.body = val("rf-body");
        if (st.cat === "leave") {
          Object.assign(p, { leave_type: val("rf-lt"), start_date: val("rf-start"), end_date: val("rf-end"), days_requested: val("rf-days"), template_version_id: R.tpl.leave_request_body?.id });
          p.details = { notes: val("rf-notes") };
        } else if (st.cat === "leave_change") {
          Object.assign(p, { original_request_id: orig?.id, start_date: val("rf-start"), end_date: val("rf-end") });
        } else p.details = { subject: val("rf-subject") };
      }
    }
    return p;
  }
  async function uploadFiles(id) {
    for (const f of st.files) await S.api.reqAttach(id, await fileToPayload(f));
  }
  async function save(submit) {
    if (!st.code) throw new Error("Επιλέξτε εργαζόμενο.");
    const p = collect();
    let id, ver;
    if (existing) { const r = await S.api.reqUpdateDraft(existing.id, p, existing.version); id = existing.id; ver = r.version; }
    else { const r = await S.api.reqCreate(p); id = r.id; ver = r.version; }
    if (st.files.length) { await uploadFiles(id); }
    if (submit) { const cur = await S.api.request(id); await S.api.reqSubmit(id, cur.version); }
    invalidate();
    return id;
  }
  function bindActions() {
    const run = (submit) => async (ev) => {
      ev.preventDefault();
      const btn = ev.currentTarget; btn.disabled = true; $("#rf-msg").textContent = "";
      try { const id = await save(submit); toast(submit ? "Υποβλήθηκε." : "Αποθηκεύτηκε ως πρόχειρο."); location.hash = `#/request?id=${id}`; }
      catch (e) { $("#rf-msg").textContent = e.message; btn.disabled = false; }
    };
    $("#rf-save") && ($("#rf-save").onclick = run(false));
    $("#rf-submit") && ($("#rf-submit").onclick = run(true));
    $("#rf-fill") && ($("#rf-fill").onclick = async (ev) => {
      ev.preventDefault();
      try {
        if (!st.code) throw new Error("Επιλέξτε εργαζόμενο.");
        const id = await save(false);
        await enterFill({ kind: "request", label: CATEGORIES[st.cat], start: () => S.api.fillStartRequest(id), returnTo: `#/request?id=${id}` });
      } catch (e) { $("#rf-msg").textContent = e.message; }
    });
  }
  $("#rf-emp").onchange = (e) => { st.code = e.target.value; drawFields(); };
  $("#rf-cat").onchange = (e) => { st.cat = e.target.value; st.bodyEdited = false; drawFields(); };
  $$("#rf-mode .chip").forEach((c) => (c.onclick = () => { st.mode = c.dataset.mode; drawFields(); }));
  $("#rf").onsubmit = (e) => e.preventDefault();
  drawFields();
}

// ═══════════════════════ Καρτέλα αιτήματος ═══════════════════════
const ACTION_GR = {
  create: "Δημιουργία προχείρου", submit: "Υποβολή", assign: "Ανάθεση / ανάληψη", forward_gm: "Εισήγηση HR → ΓΔ",
  warning_draft_saved: "Προσχέδιο προειδοποίησης (HR)", warning_draft_sent: "Προσχέδιο → απόφαση ΓΔ", decide: "Απόφαση", revise: "Αναθεώρηση απόφασης",
  info_provided: "Διευκρινίσεις", notified: "Ενημέρωση εργαζομένου", implemented: "Υλοποίηση", report_closed: "Ολοκλήρωση εξέτασης",
  warning_communicated: "Κοινοποίηση προειδοποίησης", attachment: "Συνημμένο", fill_opened: "Άνοιγμα φόρμας εργαζομένου", employee_completed: "Ο εργαζόμενος ολοκλήρωσε τη φόρμα",
  impl_claimed: "Ανάληψη υλοποίησης (manager)", leave_backfill: "Μεταφορά στις ημέρες άδειας (3.0)", leave_cancelled: "Ακύρωση άδειας", leave_partially_cancelled: "Μερική ακύρωση άδειας",
  leave_changed: "Αλλαγή ημερομηνιών άδειας", overdraw_approved: "Ειδική έγκριση υπέρβασης (ΓΔ)", task_added: "Εργασία HR/λογιστηρίου", task_done: "Ολοκλήρωση εργασίας",
};
const OUTCOME_GR = { approve: "Έγκριση", reject: "Απόρριψη", needs_info: "Απαιτούνται διευκρινίσεις" };

export async function requestView(params) {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Αιτήματα & Αναφορές"));
  const id = params.get("id");
  if (params.get("edit")) { const r = await S.api.request(id); return requestNew(new URLSearchParams(), r); }
  const [r, R] = await Promise.all([S.api.request(id), hrRefs()]);
  S.api.notifRead(id).then((n) => { if (n) window.dispatchEvent(new Event("mg:answers")); }).catch(() => {});
  const isLeave = ["leave", "leave_change"].includes(r.category);
  const [L, T] = await Promise.all([isLeave ? S.api.leaveCheck(id).catch(() => null) : null, can.decide() ? S.api.requestTasks(id).catch(() => []) : []]);
  const flow = flowOf(r.category);
  const cur = r.decisions.find((x) => !x.superseded_at);
  const me = S.me.email, rl = role();
  const isOwner = rl === "owner", isHR = rl === "hr", isMgr = rl === "manager";
  const open = ["submitted", "under_review"].includes(r.status);

  // Διαθέσιμες ενέργειες (ο server ελέγχει ξανά κάθε μία)
  const A = [];
  if (r.status === "draft") {
    if (r.entry_mode !== "employee_fill" || r.written_by) A.push(["edit", "Επεξεργασία", ""]);
    if (r.entry_mode === "employee_fill" && !String(r.written_by || "").startsWith("employee:")) A.push(["fill", "Άνοιγμα φόρμας εργαζομένου", "primary"]);
    if (r.entry_mode === "employee_fill" && String(r.written_by || "").startsWith("employee:")) { A.push(["mnote", "Εισήγηση manager", ""]); A.push(["refill", "Ξανά στον εργαζόμενο", ""]); }
    A.push(["submit", "Έλεγχος & υποβολή", "primary"]);
    A.push(["delete", "Διαγραφή προχείρου", "danger"]);
  }
  if (can.decide()) {
    if (open || r.status === "needs_info" || r.status === "awaiting_gm") A.push(["assign", r.assignee ? "Ανάθεση" : "Ανάληψη", ""]);
    if (flow === "gm" && open) A.push(["forward", "Εισήγηση & προώθηση στη ΓΔ", isHR ? "primary" : ""]);
    if (flow === "leave" && open && Number(r.leave_excess) > 0 && !isOwner) A.push(["forward", "Προώθηση στη ΓΔ (υπέρβαση υπολοίπου)", "primary"]);
    if (flow === "warning" && (open || r.status === "awaiting_gm")) A.push(["wdraft", r.internal?.warning_draft ? "Επεξεργασία προσχεδίου" : "Σύνταξη προσχεδίου", isHR ? "primary" : ""]);
    if (open || r.status === "awaiting_gm" || (r.status === "needs_info" && false)) {
      if (flow === "report") A.push(["needs_info", "Ζήτηση διευκρινίσεων", ""]);
      else if (["leave", "generic"].includes(flow) || isOwner) A.push(["decide", isOwner && ["gm", "warning"].includes(flow) ? "Τελική απόφαση ΓΔ" : "Απόφαση", "primary"]);
      else A.push(["needs_info", "Ζήτηση διευκρινίσεων", ""]);
    }
    if (flow === "report" && open) A.push(["complete", "Ολοκλήρωση εξέτασης", "primary"]);
    if (r.status === "approved" && flow === "warning") A.push(["complete", "Κοινοποίηση προειδοποίησης", "primary"]);
    if (["approved", "completed"].includes(r.status) && flow !== "report") A.push(["task", "Εργασία για HR / λογιστήριο", "ghost"]);
    if (isOwner && ["approved", "rejected"].includes(r.status)) A.push(["decide", "Αναθεώρηση απόφασης", ""]);
  }
  if (r.status === "needs_info") A.push(["info", "Συμπλήρωση διευκρινίσεων", "primary"]);
  // Υλοποίηση: Εγκρίθηκε → Ενημερώθηκε ο εργαζόμενος → Ανάληψη (manager) → Ολοκληρώθηκε
  if (can.implement() && r.status === "approved" && ["leave", "generic", "gm"].includes(flow) && r.notified_at) {
    if (!r.impl_claimed_by) A.push(["claim", "Αναλαμβάνω την υλοποίηση", "primary"]);
    else A.push(["implement", "Ολοκλήρωση υλοποίησης", "primary"]);
  }
  const activeDays = L?.active_days?.length || 0;
  if (r.category === "leave" && ["approved", "completed"].includes(r.status) && activeDays && can.createRequests()) A.push(["change", "Αλλαγή ημερομηνιών", ""]);
  if (isLeave && activeDays && can.leaveCancel()) A.push(["lcancel", "Ακύρωση άδειας (ολική / μερική)", "danger"]);
  if (flow !== "warning" && ["approved", "rejected", "needs_info"].includes(r.status) && !r.notified_at && (isMgr || can.decide())) A.push(["notified", "Ενημέρωσα τον εργαζόμενο", ""]);
  if (r.status !== "completed" && !(isMgr && !["draft", "needs_info"].includes(r.status))) A.push(["attach", "Προσθήκη συνημμένου", "ghost"]);

  const kv = (pairs) => `<dl class="kv">${pairs.filter(([, x]) => x !== null && x !== undefined && x !== "").map(([k, x]) => `<dt>${k}</dt><dd>${x}</dd>`).join("")}</dl>`;
  const decisionHtml = (x) => `<div class="decision ${x.superseded_at ? "old" : ""}">
    <div class="row-actions" style="justify-content:space-between"><strong>${OUTCOME_GR[x.outcome]}${x.is_revision ? " · αναθεώρηση" : ""}</strong>
      <span class="muted small">${h(x.decided_by)} (${x.decided_role === "owner" ? "ΓΔ" : "HR"}) · ${athens(x.decided_at)}${x.superseded_at ? ` · αντικαταστάθηκε ${athens(x.superseded_at)}` : " · ισχύει"}</span></div>
    ${x.outcome === "approve" && x.approved_start ? `<p class="small" style="margin-top:6px">Εγκρίθηκε: ${dmy(x.approved_start)} – ${dmy(x.approved_end)} · ${daysWord(x.approved_days)} ημέρες</p>` : ""}
    ${x.reason_label ? `<p class="small" style="margin-top:6px">Λόγος: <strong>${h(x.reason_label)}</strong> — ${h(x.reason_text)}${x.alternative ? `<br>Εναλλακτικό διάστημα: ${h(x.alternative)}` : ""}</p>` : ""}
    ${x.info_requested ? `<p class="small" style="margin-top:6px">Ζητήθηκαν: ${h(x.info_requested)}</p>` : ""}
    <div class="statement" style="margin-top:8px">${h(x.message)}</div></div>`;

  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">${h(r.ref)} · ${r.process === "manager" ? "Αναφορά manager" : "Αίτημα εργαζομένου"}</div>
    <h1>${h(CATEGORIES[r.category])}${r.leave_type_label ? ` · ${h(r.leave_type_label)}` : ""}</h1>
    <p class="muted">${reqBadge(r.status)} <a href="#/employee?code=${encodeURIComponent(r.employee_code)}"><strong>${h(r.employee_name)}</strong></a> · ${h(r.employee_code)} · ${h(r.store)} · ${h(r.company)}${r.specialty ? " · " + h(r.specialty) : ""}</p></div>
    <a class="btn" href="#/requests">← Αιτήματα</a></div>
  <div class="note" style="margin-bottom:16px">${h(FLOW_NOTE[flow])}</div>
  <div class="grid g2-1">
    <div>
      <div class="card"><h3>Αίτημα</h3>
        ${r.category === "leave" ? kv([["Είδος άδειας", h(r.leave_type_label)], ["Διάστημα", r.start_date ? `${dmy(r.start_date)} έως και ${dmy(r.end_date)}` : ""], ["Ημερολογιακές ημέρες", calendarDays(r.start_date, r.end_date)], ["Αιτούμενες ημέρες άδειας", daysWord(r.days_requested)]]) : ""}
        ${r.details?.subject ? kv([["Θέμα", h(r.details.subject)]]) : ""}
        ${r.body ? `<div class="statement">${h(r.body)}</div>` : r.process === "employee" ? `<p class="muted" style="margin-top:10px">${r.entry_mode === "employee_fill" ? "Ο εργαζόμενος δεν έχει συμπληρώσει ακόμη το κείμενο." : "Δεν υπάρχει κείμενο ακόμη."}</p>` : ""}
        ${r.details?.notes ? kv([["Παρατηρήσεις", h(r.details.notes)]]) : ""}
        ${r.process === "manager" ? kv([["Ημερομηνία περιστατικού", dmy(r.incident_date)], ["Περιγραφή", h(r.details.description)], ["Παραδείγματα", h(r.details.examples)], ["Προηγούμενη συζήτηση", h(r.details.prior_discussion)], ["Προτεινόμενη ενέργεια", h(r.details.proposed_action)]]) : ""}
        ${r.manager_note ? `<h4 style="margin-top:16px">Εισήγηση manager</h4><p class="small" style="white-space:pre-wrap;margin-top:6px">${h(r.manager_note)}</p>` : ""}
        ${r.attachments.length ? `<h4 style="margin-top:16px">Συνημμένα</h4>${r.attachments.map((a) => `<div class="list-item"><div class="grow">${h(a.filename)}<div class="muted small">${Math.ceil(a.size / 1024)} KB · ${h(who(a.uploaded_by))} · ${athens(a.uploaded_at)}</div></div><button class="btn sm" data-att="${h(a.id)}">Λήψη</button></div>`).join("")}` : ""}
      </div>
      ${L ? leavePanel(r, L) : ""}
      ${T.length ? `<div class="card" style="margin-top:16px"><h3>Εργασίες HR / λογιστηρίου</h3>${T.map((t) => `<div class="list-item"><div class="grow small"><strong>${t.owner_role === "hr" ? "HR" : "Λογιστήριο"}:</strong> ${h(t.description)}<div class="muted">${h(t.created_by)} · ${athens(t.created_at)}${t.done_at ? ` · ολοκληρώθηκε ${athens(t.done_at)} από ${h(t.done_by)}${t.done_note ? " — " + h(t.done_note) : ""}` : ""}</div></div>${t.status === "done" ? `<span class="badge b-signed">Ολοκληρώθηκε</span>` : (role() === t.owner_role || isOwner) ? `<button class="btn sm" data-tdone="${t.id}">Ολοκλήρωση</button>` : `<span class="badge b-pending">Ανοιχτή</span>`}</div>`).join("")}</div>` : ""}
      ${r.internal && (r.internal.hr_note || r.internal.warning_draft) ? `<div class="card" style="margin-top:16px"><h3>Εσωτερικά HR <span class="muted small">(μόνο ΓΔ & HR)</span></h3>
        ${r.internal.hr_note ? `<h4 style="margin-top:10px">Εισήγηση HR</h4><p class="small" style="white-space:pre-wrap">${h(r.internal.hr_note)}</p><p class="muted small">${h(r.internal.hr_note_by)} · ${athens(r.internal.hr_note_at)}</p>` : ""}
        ${r.internal.warning_draft ? `<h4 style="margin-top:10px">Προσχέδιο προειδοποίησης</h4><div class="statement">${h(r.internal.warning_draft)}</div><p class="muted small">${h(r.internal.warning_draft_by)} · ${athens(r.internal.warning_draft_at)}</p>` : ""}</div>` : ""}
      <div class="card" style="margin-top:16px"><h3>Αποφάσεις</h3>
        ${r.decisions.length ? r.decisions.slice().reverse().map(decisionHtml).join("") : `<p class="muted" style="margin-top:8px">Δεν υπάρχει απόφαση ακόμη.</p>`}
      </div>
    </div>
    <div>
      <div class="card"><h3>Ενέργειες</h3>
        <div class="stack-actions">${A.length ? A.map(([k, l, c]) => `<button class="btn ${c}" data-act="${k}">${h(l)}</button>`).join("") : `<p class="muted small">Καμία διαθέσιμη ενέργεια για τον ρόλο σας.</p>`}</div>
      </div>
      <div class="card" style="margin-top:16px"><h3>Στοιχεία</h3>
        ${kv([["Διατύπωσε", h(who(r.stated_by))], ["Συμπλήρωσε το κείμενο", h(who(r.written_by))], ["Υπέβαλε", h(who(r.submitted_by))], ["Υποβλήθηκε", r.submitted_at ? athens(r.submitted_at) : "—"],
          ["Δημιουργήθηκε", `${athens(r.created_at)} · ${h(r.created_by)}`], ["Υπεύθυνος χειρισμού", h(r.assignee || "—")],
          ["Ενημέρωση εργαζομένου", r.notified_at ? `${athens(r.notified_at)} · ${h(r.notified_by)}${r.notify_note ? ` · ${h(r.notify_note)}` : ""}` : "—"],
          ["Ανάληψη υλοποίησης", r.impl_claimed_by ? `${athens(r.impl_claimed_at)} · ${h(r.impl_claimed_by)}` : "—"],
          ["Ολοκλήρωση", r.completed_at ? `${athens(r.completed_at)} · ${h(r.completed_by)} · ${h(r.completion_note)}` : "—"]])}
      </div>
      <div class="card" style="margin-top:16px"><h3>Ιστορικό</h3>
        ${r.events.slice().reverse().map((e) => `<div class="list-item"><div class="grow"><div class="small"><strong>${h(ACTION_GR[e.action] || e.action)}</strong>${e.to_status && e.from_status !== e.to_status ? ` → ${h(REQ_STATUS[e.to_status]?.label || e.to_status)}` : ""}${e.internal ? ` <span class="muted">(εσωτερικό)</span>` : ""}</div>
          ${e.note ? `<div class="small" style="white-space:pre-wrap">${h(e.note)}</div>` : ""}<div class="muted small">${h(who(e.actor))} · ${athens(e.at)}</div></div></div>`).join("")}
      </div>
    </div>
  </div>`;

  const reload = () => { invalidate(); requestView(params); };
  const doIt = async (fn, okMsg) => { try { await fn(); toast(okMsg); reload(); } catch (e) { toast(e.message, true); } };
  $$("[data-tdone]").forEach((b) => (b.onclick = async () => { const t = await textDialog("Ολοκλήρωση εργασίας", "Σύντομη σημείωση για το τι έγινε.", "", 2); if (t !== null) doIt(() => S.api.reqTaskDone(Number(b.dataset.tdone), t), "Η εργασία ολοκληρώθηκε."); }));
  $$("[data-att]").forEach((b) => (b.onclick = async () => { try { const a = await S.api.attachment(b.dataset.att); saveBlob(base64ToBlob(a.data, a.mime), a.filename); } catch (e) { toast(e.message, true); } }));
  $$("[data-act]").forEach((b) => (b.onclick = async () => {
    const k = b.dataset.act;
    if (k === "edit") return (location.hash = `#/request?id=${r.id}&edit=1`);
    if (k === "fill" || k === "refill") {
      return enterFill({ kind: "request", label: CATEGORIES[r.category], start: () => S.api.fillStartRequest(r.id), returnTo: `#/request?id=${r.id}` }).catch((e) => toast(e.message, true));
    }
    if (k === "submit") {
      if (!(await confirmBox("Υποβολή αιτήματος", `Ελέγξατε το αίτημα του/της ${r.employee_name}; Μετά την υποβολή το κείμενο δεν αλλάζει. Η υποβολή δεν αποτελεί έγκριση.`, { ok: "Υποβολή" }))) return;
      return doIt(() => S.api.reqSubmit(r.id, r.version), "Υποβλήθηκε.");
    }
    if (k === "delete") {
      if (!(await confirmBox("Διαγραφή προχείρου", "Το πρόχειρο θα διαγραφεί. Η διαγραφή καταγράφεται στο ιστορικό ενεργειών.", { ok: "Διαγραφή", danger: true }))) return;
      try { await S.api.reqDelete(r.id, r.version); invalidate(); toast("Διαγράφηκε."); location.hash = "#/requests"; } catch (e) { toast(e.message, true); }
      return;
    }
    if (k === "mnote") {
      const t = await textDialog("Εισήγηση manager", "Η εισήγησή σας καταγράφεται χωριστά από το κείμενο του εργαζομένου.", r.manager_note || "", 3);
      if (t !== null) doIt(() => S.api.reqUpdateDraft(r.id, { manager_note: t }, r.version), "Αποθηκεύτηκε.");
      return;
    }
    if (k === "assign") return assignDialog(r, reload);
    if (k === "forward") {
      const t = await textDialog("Εισήγηση HR προς τη Γενική Διευθύντρια", "Η τελική απόφαση για αυξήσεις και αλλαγές σύμβασης ανήκει στη ΓΔ.", r.internal?.hr_note || "", 4);
      if (t !== null) doIt(() => S.api.reqForward(r.id, t, r.version), "Προωθήθηκε στη ΓΔ.");
      return;
    }
    if (k === "wdraft") return warningDraftDialog(r, R, reload);
    if (k === "decide") return decisionDialog(r, R, cur, reload);
    if (k === "needs_info") return decisionDialog(r, R, cur, reload, "needs_info");
    if (k === "info") {
      const t = await textDialog("Διευκρινίσεις", `Ζητήθηκαν: ${cur?.info_requested || ""}. Αν χρειάζεται, προσθέστε πρώτα συνημμένο.`, "", 3);
      if (t !== null) doIt(() => S.api.reqProvideInfo(r.id, t, r.version), "Καταχωρίστηκαν οι διευκρινίσεις.");
      return;
    }
    if (k === "notified") return notifiedDialog(r, reload);
    if (k === "claim") return doIt(() => S.api.reqImplClaim(r.id, r.version), "Αναλάβατε την υλοποίηση.");
    if (k === "implement") return implementDialog(r, reload);
    if (k === "change") return (location.hash = `#/request-new?kind=change&orig=${r.id}`);
    if (k === "lcancel") return cancelLeaveDialog(r, L, reload);
    if (k === "task") return taskDialog(r, reload);
    if (k === "complete") {
      const t = await textDialog(flow === "warning" ? "Κοινοποίηση προειδοποίησης" : flow === "report" ? "Ολοκλήρωση εξέτασης" : "Υλοποίηση",
        flow === "warning" ? "Πώς και πότε κοινοποιήθηκε στον εργαζόμενο (π.χ. «Παραδόθηκε ιδιοχείρως, υπογράφηκε παραλαβή»)." : flow === "report" ? "Τι αποφασίστηκε μετά την εξέταση της αναφοράς." : "Τι υλοποιήθηκε (π.χ. «Ενημερώθηκε το πρόγραμμα»).", "", 2);
      if (t !== null) doIt(() => S.api.reqComplete(r.id, t, r.version), "Ολοκληρώθηκε.");
      return;
    }
    if (k === "attach") {
      const inp = document.createElement("input"); inp.type = "file"; inp.accept = ".pdf,.jpg,.jpeg,.png,.webp,.heic";
      inp.onchange = async () => { const f = inp.files[0]; if (f) doIt(async () => S.api.reqAttach(r.id, await fileToPayload(f)), "Το συνημμένο προστέθηκε."); };
      inp.click();
    }
  }));
}

function textDialog(title, hint, value = "", rows = 3) {
  return new Promise((resolve) => {
    openDialog(`<div class="dlg-head"><h2>${h(title)}</h2><button class="icon-btn" data-close>✕</button></div>
      <p class="muted">${h(hint)}</p><textarea id="td-t" rows="${rows + 2}" maxlength="8000">${h(value)}</textarea><p id="td-m" class="form-msg"></p>
      <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="td-ok">Αποθήκευση</button></div>`, {
      onOpen(d) {
        let done = false;
        d.addEventListener("close", () => { if (!done) resolve(null); }, { once: true });
        $("#td-t").focus();
        $("#td-ok").onclick = () => { const v = $("#td-t").value.trim(); if (v.length < 3) return ($("#td-m").textContent = "Συμπληρώστε το κείμενο."); done = true; closeDialog(); resolve(v); };
      },
    });
  });
}

async function assignDialog(r, reload) {
  const list = await S.api.handlers();
  openDialog(`<div class="dlg-head"><h2>Υπεύθυνος χειρισμού</h2><button class="icon-btn" data-close>✕</button></div>
    <label>Ανάθεση σε</label><select id="as-to">${list.map((u) => `<option value="${h(u.email)}" ${u.email === (r.assignee || S.me.email) ? "selected" : ""}>${h(u.name)} · ${u.role === "owner" ? "ΓΔ" : "HR"}</option>`).join("")}</select>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="as-ok">Ανάθεση</button></div>`, {
    onOpen() { $("#as-ok").onclick = async () => { try { await S.api.reqAssign(r.id, $("#as-to").value, r.version); closeDialog(); toast("Ανατέθηκε."); reload(); } catch (e) { toast(e.message, true); } }; },
  });
}

function notifiedDialog(r, reload) {
  const now = new Date(); const pad = (n) => String(n).padStart(2, "0");
  const local = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
  openDialog(`<div class="dlg-head"><h2>Ενημέρωση εργαζομένου</h2><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Καταγράψτε πότε ενημερώσατε τον/την ${h(r.employee_name)} για την απόφαση.</p>
    <label>Πότε</label><input type="datetime-local" id="nt-at" value="${local}">
    <label>Σημείωση (προαιρετικά)</label><input id="nt-note" maxlength="300" placeholder="π.χ. προφορικά στο κατάστημα">
    <p id="nt-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="nt-ok">Καταγραφή</button></div>`, {
    onOpen() {
      $("#nt-ok").onclick = async () => {
        try { await S.api.reqNotified(r.id, new Date($("#nt-at").value).toISOString(), $("#nt-note").value, r.version); closeDialog(); toast("Καταγράφηκε."); reload(); }
        catch (e) { $("#nt-m").textContent = e.message; }
      };
    },
  });
}

function warningDraftDialog(r, R, reload) {
  const start = r.internal?.warning_draft || renderTemplate(R.tpl.warning_draft?.body, leaveVars(r));
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">Εξέταση HR</div><h2>Προσχέδιο έγγραφης προειδοποίησης</h2></div><button class="icon-btn" data-close>✕</button></div>
    <div class="note warn">Η προειδοποίηση εκδίδεται ΜΟΝΟ μετά από τελική έγκριση της Γενικής Διευθύντριας. Τίποτα δεν αποστέλλεται αυτόματα.</div>
    <label>Κείμενο</label><textarea id="wd-t" rows="12" maxlength="8000">${h(start)}</textarea><p id="wd-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn" id="wd-save">Αποθήκευση</button><button class="btn primary" id="wd-send">Αποστολή στη ΓΔ για απόφαση</button></div>`, {
    wide: true,
    onOpen() {
      const go = (send) => async () => { try { await S.api.reqWarningDraft(r.id, $("#wd-t").value, send, r.version); closeDialog(); toast(send ? "Στάλθηκε στη ΓΔ." : "Αποθηκεύτηκε."); reload(); } catch (e) { $("#wd-m").textContent = e.message; } };
      $("#wd-save").onclick = go(false); $("#wd-send").onclick = go(true);
    },
  });
}

function decisionDialog(r, R, cur, reload, only = null) {
  const flow = flowOf(r.category);
  const isLeave = r.category === "leave" || r.category === "leave_change";
  const reasons = reasonsFor(R.reasons, r);
  const revision = ["approved", "rejected"].includes(r.status);
  const outcomes = only ? [only] : flow === "warning" ? ["approve", "reject"] : revision ? ["approve", "reject"] : ["approve", "reject", "needs_info"];
  const st = { o: outcomes[0], edited: false };
  const tplKey = (o) => (isLeave ? { approve: "leave_approve", reject: "leave_reject", needs_info: "leave_needs_info" } : { approve: "generic_approve", reject: "generic_reject", needs_info: "generic_needs_info" })[o];
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(r.ref)} · ${h(r.employee_name)}</div><h2>${revision ? "Αναθεώρηση απόφασης" : flow === "warning" ? "Τελική απόφαση για την προειδοποίηση" : "Απόφαση"}</h2></div><button class="icon-btn" data-close>✕</button></div>
    ${revision ? `<div class="note warn">Η τρέχουσα απόφαση (${h(OUTCOME_GR[cur?.outcome] || "")}) θα παραμείνει στο ιστορικό ως προηγούμενη.</div>` : ""}
    <div class="chips" id="dd-o" style="margin-top:12px">${outcomes.map((o) => `<button class="chip" data-o="${o}">${OUTCOME_GR[o]}</button>`).join("")}</div>
    <div id="dd-f"></div>
    <label>Κείμενο προς τον εργαζόμενο <span class="muted">(αποθηκεύεται όπως είναι)</span></label><textarea id="dd-msg" rows="7" maxlength="8000"></textarea>
    <p class="muted small"><button class="btn sm ghost" id="dd-regen" type="button">↻ Από το πρότυπο</button></p>
    <p id="dd-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="dd-ok">Καταχώριση απόφασης</button></div>`, {
    wide: true,
    onOpen() {
      const vars = () => {
        const extra = {};
        if (isLeave && st.o === "approve") Object.assign(extra, { έναρξη: dmy($("#dd-s")?.value), λήξη: dmy($("#dd-e")?.value),
          ημέρες: daysWord(st.plan?.annual ? String($$(".dd-ch").reduce((a, x) => a + Number(x.value), 0) || st.plan.requested) : $("#dd-d")?.value) });
        if (st.o === "reject") Object.assign(extra, { αιτιολογία: $("#dd-rt")?.value.trim().replace(/\.$/, ""), εναλλακτικό_διάστημα: $("#dd-alt")?.value.trim() || "Προς συνεννόηση" });
        if (st.o === "needs_info") extra.στοιχεία = $("#dd-info")?.value.trim();
        return leaveVars(r, extra);
      };
      const regen = () => {
        if (flow === "warning" && st.o === "approve") { $("#dd-msg").value = r.internal?.warning_draft || ""; return; }
        $("#dd-msg").value = renderTemplate(R.tpl[tplKey(st.o)]?.body, vars()); st.edited = false;
      };
      const draw = () => {
        $$("#dd-o .chip").forEach((c) => c.classList.toggle("on", c.dataset.o === st.o));
        let f = "";
        if (st.o === "approve" && isLeave) f = `<div class="grid g3"><div><label>Εγκεκριμένη έναρξη</label><input type="date" id="dd-s" value="${h(r.start_date)}"></div>
          <div><label>Εγκεκριμένη λήξη</label><input type="date" id="dd-e" value="${h(r.end_date)}"></div><div id="dd-dbox"><label>Εγκεκριμένες ημέρες άδειας</label><input id="dd-d" inputmode="decimal" value="${h(r.days_requested || "")}"></div></div>
          <div id="dd-plan" style="margin-top:10px"><div class="spinner"></div></div>`;
        if (st.o === "approve" && flow === "warning") f = `<div class="note warn" style="margin-top:12px">Εγκρίνετε το τελικό κείμενο της προειδοποίησης (μπορείτε να το διορθώσετε). Η κοινοποίηση γίνεται μετά από το HR.</div>`;
        if (st.o === "reject") f = `<label>Λόγος απόρριψης</label><select id="dd-r"><option value="">— επιλέξτε —</option>${reasons.map((x) => `<option value="${x.code}">${h(x.label)}</option>`).join("")}</select>
          ${isLeave && !reasons.some((x) => x.code === "ops_needs") ? `<p class="muted small" style="margin-top:6px">Για ${h(r.leave_type_label)} δεν εμφανίζονται λόγοι επιχειρησιακών αναγκών.</p>` : ""}
          <label>Συγκεκριμένη αιτιολογία</label><textarea id="dd-rt" rows="3" maxlength="2000"></textarea>
          ${isLeave ? `<label>Προτεινόμενο εναλλακτικό διάστημα</label><input id="dd-alt" maxlength="200" placeholder="Προς συνεννόηση">` : ""}`;
        if (st.o === "needs_info") f = `<label>Ποια στοιχεία / δικαιολογητικά απαιτούνται</label><textarea id="dd-info" rows="2" maxlength="2000"></textarea>
          <p class="muted small" style="margin-top:6px">Το αίτημα μένει σε εκκρεμότητα — δεν απορρίπτεται.</p>`;
        $("#dd-f").innerHTML = f;
        $$("#dd-f input, #dd-f textarea").forEach((x) => (x.oninput = () => { if (!st.edited) regen(); }));
        $("#dd-r") && ($("#dd-r").onchange = () => {
          const reason = R.reasons.find((x) => x.code === $("#dd-r").value);
          if (reason?.template_key && R.tpl[reason.template_key] && !$("#dd-rt").value.trim()) {
            $("#dd-rt").value = renderTemplate(R.tpl[reason.template_key].body, { περίοδος: "[περιγραφή περιόδου ή δραστηριότητας]" });
          }
          if (!st.edited) regen();
        });
        regen();
        if (st.o === "approve" && isLeave) {
          const loadPlan = async () => {
            try {
              st.plan = await S.api.leavePreview(r.employee_code, $("#dd-s").value, $("#dd-e").value, r.leave_type || L0?.leave_type, r.id);
              drawPlan();
            } catch (e) { $("#dd-plan") && ($("#dd-plan").innerHTML = `<div class="note bad">${h(e.message)}</div>`); }
          };
          $("#dd-s").onchange = $("#dd-e").onchange = loadPlan;
          loadPlan();
        }
      };
      const L0 = r.original_request_id ? { leave_type: null } : null;
      const drawPlan = () => {
        const P = st.plan; if (!P || !$("#dd-plan") || st.o !== "approve") return;
        $("#dd-dbox").hidden = !!P.annual;
        const charged = () => $$(".dd-ch").reduce((a, x) => a + Number(x.value), 0);
        const base = P.annual ? `<div class="table-wrap" style="max-height:220px"><table><thead><tr><th>Ημέρα</th><th>Εργάσιμη</th><th class="r">Χρέωση</th></tr></thead><tbody>
          ${P.days.map((d) => `<tr><td class="small">${dmy(d.day)}${d.holiday ? ` <span class="muted">(${h(d.holiday)})</span>` : ""}</td><td class="small">${d.workday === null ? `<span class="badge b-missing">άγνωστο</span>` : d.workday ? "ναι" : "όχι"}</td>
            <td class="r"><select class="dd-ch" data-day="${d.day}" ${d.workday === false ? "disabled" : ""}>${[1, 0.5, 0].map((v) => `<option value="${v}" ${Number(d.charge) === v ? "selected" : ""}>${String(v).replace(".", ",")}</option>`).join("")}</select></td></tr>`).join("")}</tbody></table></div>` : `<p class="muted small">Το είδος αυτό δεν χρεώνεται στην κανονική άδεια· καταχωρίζονται ${P.days.length} ημερολογιακές ημέρες απουσίας.</p>`;
        const ex = Number(P.excess || 0);
        $("#dd-plan").innerHTML = `${base}
          ${P.annual ? `<p class="small" style="margin-top:6px">Ημέρες χρέωσης: <strong id="dd-sum">${String(P.requested).replace(".", ",")}</strong> · Διαθέσιμο βάσει αναλογίας: <strong>${P.available === null ? "—" : String(P.available).replace(".", ",")}</strong>${ex > 0 ? ` · <span class="badge b-voided">Υπέρβαση ${String(P.excess).replace(".", ",")}</span>` : ""}</p>` : ""}
          ${P.base_missing ? `<div class="note warn">Δεν έχει οριστεί ετήσια βάση άδειας για τον εργαζόμενο — δεν υπολογίζεται υπέρβαση. Ορίστε την από την καρτέλα (Άδειες).</div>` : ""}
          ${P.unknown_days ? `<div class="note warn">Λείπει πενθήμερο/εξαήμερο ή πρόγραμμα: επιλέξτε χειροκίνητα τη χρέωση κάθε ημέρας.</div>` : ""}
          ${P.conflicts?.length ? `<div class="note bad">Επικάλυψη με ${P.conflicts.map((c) => h(c.ref)).join(", ")}.</div>` : ""}
          ${P.sick?.message ? `<div class="note warn">${h(P.sick.message)}</div>` : ""}
          ${ex > 0 ? (can.overdraw() ? `<label class="check" style="margin-top:6px"><input type="checkbox" id="dd-over"> Ειδική έγκριση υπέρβασης αναλογικού υπολοίπου (Γενική Διεύθυνση) — το αρνητικό υπόλοιπο διατηρείται</label>`
                       : `<div class="note bad">Υπέρβαση αναλογικού υπολοίπου: την έγκριση δίνει μόνο η Γενική Διευθύντρια. Μπορείτε να προωθήσετε, να απορρίψετε ή να ζητήσετε διευκρινίσεις.</div>`) : ""}`;
        $$(".dd-ch").forEach((x) => (x.onchange = () => { $("#dd-sum").textContent = String(charged()).replace(".", ","); st.daysEdited = true; if (!st.edited) regen(); }));
        if (!st.edited) regen();
      };
      $$("#dd-o .chip").forEach((c) => (c.onclick = () => { st.o = c.dataset.o; draw(); }));
      $("#dd-msg").oninput = () => (st.edited = true);
      $("#dd-regen").onclick = regen;
      $("#dd-ok").onclick = async () => {
        const msg = $("#dd-msg").value.trim();
        if (/\{[^{}\s]+\}|\[περιγραφή περιόδου/.test(msg + ($("#dd-rt")?.value || ""))) return ($("#dd-m").textContent = "Υπάρχουν ασυμπλήρωτα πεδία στο κείμενο ({…} ή […]).");
        const p = { message: msg, template_version_id: flow === "warning" ? null : R.tpl[tplKey(st.o)]?.id };
        if (st.o === "approve" && isLeave) {
          Object.assign(p, { approved_start: $("#dd-s").value, approved_end: $("#dd-e").value, approved_days: $("#dd-d").value });
          if (st.plan?.annual) p.days = $$(".dd-ch").map((x) => ({ day: x.dataset.day, charge: Number(x.value) }));
          if ($("#dd-over")?.checked) p.overdraw_ok = true;
        }
        if (st.o === "reject") Object.assign(p, { reason_code: $("#dd-r").value, reason_text: $("#dd-rt").value.trim(), alternative: $("#dd-alt")?.value.trim() || null });
        if (st.o === "needs_info") p.info = $("#dd-info").value.trim();
        const btn = $("#dd-ok"); btn.disabled = true;
        try { await S.api.reqDecide(r.id, st.o, p, r.version); closeDialog(); toast("Η απόφαση καταχωρίστηκε."); reload(); }
        catch (e) { $("#dd-m").textContent = e.message; btn.disabled = false; }
      };
      draw();
    },
  });
}

// ═══════════════════════ Έκδοση 3: άδειες & υλοποίηση ═══════════════════════
const n2 = (v) => (v === null || v === undefined ? "—" : Number(v).toLocaleString("el-GR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));

/** Προεπισκόπηση στη φόρμα αιτήματος: ημέρες χρέωσης, διαθέσιμο, υπέρβαση, αναρρωτική, επικαλύψεις. */
async function leavePreviewBox(el, code, a, b, type, reqId) {
  if (!el) return;
  if (!code || !a || !b || !type || b < a || !(can.leave() || can.requests())) { el.innerHTML = ""; return; }
  try {
    const P = await S.api.leavePreview(code, a, b, type, reqId);
    if (!el.isConnected) return;
    const ex = Number(P.excess || 0);
    el.innerHTML = `<div class="note ${ex > 0 || P.conflicts?.length ? "warn" : ""}" style="margin-top:8px">
      ${P.annual ? `Ημέρες χρέωσης (από το πρόγραμμα / σύστημα εργασίας, χωρίς αργίες): <strong>${n2(P.requested)}</strong> · Διαθέσιμο υπόλοιπο βάσει αναλογίας: <strong>${P.available === null ? "—" : n2(P.available)}</strong>
        ${ex > 0 ? `<br><strong>Υπέρβαση: ${n2(P.excess)} ημέρες.</strong> Η υποβολή επιτρέπεται· απαιτείται ειδική έγκριση της Γενικής Διευθύντριας.` : ""}
        ${P.base_missing ? `<br>Δεν έχει οριστεί ετήσια βάση άδειας — δεν υπολογίζεται υπόλοιπο.` : ""}
        ${P.unknown_days ? `<br>Λείπει πενθήμερο/εξαήμερο ή πρόγραμμα για ${P.unknown_days} ημέρες.` : ""}
        ${P.balance?.prev_state === "usable" && Number(P.balance.prev_balance) > 0 ? `<br>Υπόλοιπο ${P.balance.prev_year}: ${n2(P.balance.prev_balance)} (έως ${dmy(P.balance.prev_deadline)}) — χρεώνεται πρώτα για άδειες έως 31/03.` : ""}`
      : `Δεν χρεώνεται στην κανονική άδεια.`}
      ${P.sick?.message ? `<br><strong>${h(P.sick.message)}</strong> (η καταχώριση δεν μπλοκάρεται)` : ""}
      ${P.conflicts?.length ? `<br><strong>Υπάρχει ήδη άδεια ή εκκρεμές αίτημα στις ίδιες ημερομηνίες (${P.conflicts.map((c) => h(c.ref)).join(", ")}).</strong>` : ""}
    </div>`;
  } catch (e) { if (el.isConnected) el.innerHTML = `<p class="muted small">${h(e.message)}</p>`; }
}

/** Πίνακας άδειας στην καρτέλα αιτήματος */
function leavePanel(r, L) {
  const ex = Number(L.excess || 0);
  return `<div class="card" style="margin-top:16px"><h3>Άδεια — υπολογισμός server</h3>
    ${L.original ? `<p class="small" style="margin-top:6px">Αλλάζει την άδεια <a href="#/request?id=${h(L.original.id)}">${h(L.original.ref)}</a> (${dmy(L.original.start)} – ${dmy(L.original.end)}). Μέχρι την έγκριση ισχύει η αρχική.</p>` : ""}
    ${L.annual ? `<div class="grid g3" style="margin-top:8px">
      <div><div class="muted small">Αιτούμενες ημέρες χρέωσης</div><strong>${n2(L.requested)}</strong></div>
      <div><div class="muted small">Διαθέσιμο βάσει αναλογίας</div><strong>${L.available === null ? "—" : n2(L.available)}</strong></div>
      <div><div class="muted small">Υπέρβαση</div><strong class="${ex > 0 ? "bad-t" : ""}">${L.excess === null ? "—" : n2(L.excess)}</strong></div></div>
      ${ex > 0 && !["approved", "completed", "rejected"].includes(r.status) ? `<div class="note warn" style="margin-top:8px">Απαιτείται ειδική έγκριση της Γενικής Διευθύντριας. Το HR δεν εγκρίνει την υπέρβαση.</div>` : ""}
      ${L.base_missing ? `<div class="note warn" style="margin-top:8px">Δεν έχει οριστεί ετήσια βάση άδειας για τον εργαζόμενο.</div>` : ""}` : `<p class="muted small" style="margin-top:6px">Δεν χρεώνεται στην κανονική άδεια.</p>`}
    ${L.sick?.message ? `<div class="note warn" style="margin-top:8px">${h(L.sick.message)}</div>` : ""}
    ${L.active_days?.length ? `<p class="small" style="margin-top:8px">Ενεργές ημέρες στο ημερολόγιο: <strong>${L.active_days.length}</strong>${L.annual ? ` · χρέωση ${n2(L.active_days.reduce((a, d) => a + Number(d.charge), 0))}` : ""}</p>` : ""}
  </div>`;
}

function implementDialog(r, reload) {
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(r.ref)}</div><h2>Ολοκλήρωση υλοποίησης</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Τι υλοποιήθηκε (π.χ. «Ενημερώθηκε το πρόγραμμα της εβδομάδας»). Η ολοκλήρωση δεν αλλάζει την εγκεκριμένη απόφαση.</p>
    <label>Σχόλιο</label><textarea id="im-n" rows="3" maxlength="2000"></textarea>
    <label>Δικαιολογητικό (προαιρετικό)</label><input type="file" id="im-f" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic">
    <p id="im-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="im-ok">Ολοκλήρωση</button></div>`, {
    onOpen() {
      $("#im-ok").onclick = async () => {
        try {
          const f = $("#im-f").files[0];
          await S.api.reqImplComplete(r.id, $("#im-n").value.trim(), f ? await fileToPayload(f) : null, r.version);
          closeDialog(); toast("Η υλοποίηση ολοκληρώθηκε."); reload();
        } catch (e) { $("#im-m").textContent = e.message; }
      };
    },
  });
}

function cancelLeaveDialog(r, L, reload) {
  const days = L?.active_days || [];
  openDialog(`<div class="dlg-head"><div><div class="eyebrow">${h(r.ref)} · ${h(r.employee_name)}</div><h2>Ακύρωση εγκεκριμένης άδειας</h2></div><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Επιλέξτε τις ημερομηνίες που ακυρώνονται (όλες = ολική ακύρωση). Επιστρέφονται μόνο οι αντίστοιχες χρεωμένες ημέρες, στο σωστό έτος. Ενημερώνονται ημερολόγιο, πρόγραμμα και manager.</p>
    <div class="chips" style="max-height:220px;overflow:auto">${days.map((d) => `<label class="chip"><input type="checkbox" class="lc-d" value="${d.day}" checked> ${dmy(d.day)}${Number(d.charge) ? ` <span class="muted small">(${String(d.charge).replace(".", ",")})</span>` : ""}</label>`).join("")}</div>
    <label>Αιτιολογία</label><textarea id="lc-r" rows="2" maxlength="1000"></textarea>
    <p id="lc-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn danger" id="lc-ok">Ακύρωση ημερών</button></div>`, {
    onOpen() {
      $("#lc-ok").onclick = async () => {
        const sel = $$(".lc-d:checked").map((x) => x.value);
        if (!sel.length) return ($("#lc-m").textContent = "Επιλέξτε ημερομηνίες.");
        try {
          const res = await S.api.leaveCancel(r.id, sel.length === days.length ? null : sel, $("#lc-r").value.trim());
          closeDialog(); toast(res.kind === "total" ? "Η άδεια ακυρώθηκε." : `Ακυρώθηκαν ${res.days} ημέρες.`); reload();
        } catch (e) { $("#lc-m").textContent = e.message; }
      };
    },
  });
}

function taskDialog(r, reload) {
  openDialog(`<div class="dlg-head"><h2>Εργασία για HR / λογιστήριο</h2><button class="icon-btn" data-close>✕</button></div>
    <p class="muted">Εξειδικευμένη ενέργεια που παρακολουθείται χωριστά από την υλοποίηση του manager (π.χ. «Έκδοση βεβαίωσης αποδοχών»).</p>
    <label>Υπεύθυνος</label><select id="tk-r"><option value="hr">HR</option><option value="accounting">Λογιστήριο</option></select>
    <label>Ενέργεια</label><textarea id="tk-t" rows="2" maxlength="1000"></textarea><p id="tk-m" class="form-msg"></p>
    <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn primary" id="tk-ok">Προσθήκη</button></div>`, {
    onOpen() { $("#tk-ok").onclick = async () => { try { await S.api.reqTaskAdd(r.id, $("#tk-r").value, $("#tk-t").value.trim()); closeDialog(); toast("Η εργασία προστέθηκε."); reload(); } catch (e) { $("#tk-m").textContent = e.message; } }; },
  });
}
