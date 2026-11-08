// Ρυθμίσεις → Ρόλοι & Δικαιώματα: επεξεργάσιμος πίνακας (μόνο Γενική Διευθύντρια).
// Οι αλλαγές εφαρμόζονται στον server, με ιστορικό και προστασία από απώλεια πρόσβασης της διαχειρίστριας.
import { S } from "./core.js";
import { $, $$, h, toast, ROLE_GR } from "./util.js";
import { athens, demoNotice } from "./hr-common.js";

const view = () => $("#view");
const ROLES = ["owner", "hr", "accounting", "manager", "trainer"];
const SCOPE_GR = { all: "Όλα τα καταστήματα", own_store: "Μόνο το κατάστημά του", assigned: "Όσα ορίζονται ανά χρήστη" };

export async function permissionsView() {
  if (S.api.mode === "demo") return (view().innerHTML = demoNotice("Ρόλοι & Δικαιώματα"));
  const M = await S.api.permMatrix();
  const draft = JSON.parse(JSON.stringify(M.grants));
  const scopes = { ...M.scopes };
  const modules = [...new Set(M.permissions.map((p) => p.module))];
  const changes = () => {
    const out = [];
    for (const r of ROLES) for (const p of M.permissions) if (draft[r][p.code] !== M.grants[r][p.code]) out.push({ role: r, perm: p.code, allowed: draft[r][p.code] });
    const sc = {}; for (const r of ROLES) if (scopes[r] !== M.scopes[r]) sc[r] = scopes[r];
    return { out, sc };
  };
  const locked = (r, p) => p.fixed_roles || (r === "owner" && ["users.manage", "permissions.manage"].includes(p.code));
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Διαχείριση</div><h1>Ρόλοι & Δικαιώματα</h1>
    <p class="muted">Δικαιώματα ανά ενότητα και ενέργεια. Τα εφαρμόζει ο server σε κάθε ενέργεια — η οθόνη απλώς δεν δείχνει ό,τι δεν επιτρέπεται. Νέες ενότητες δεν δίνουν δικαιώματα «από προεπιλογή».</p></div></div>
  <div class="card">
    <div class="table-wrap"><table class="perm-table"><thead><tr><th>Ενότητα · ενέργεια</th>${ROLES.map((r) => `<th class="c">${ROLE_GR[r]}</th>`).join("")}</tr>
      <tr class="scope-row"><th>Πεδίο πρόσβασης σε καταστήματα</th>${ROLES.map((r) => `<th class="c"><select data-scope="${r}" ${r === "owner" ? "disabled" : ""}>${Object.entries(SCOPE_GR).map(([k, v]) => `<option value="${k}" ${scopes[r] === k ? "selected" : ""}>${v}</option>`).join("")}</select></th>`).join("")}</tr></thead>
      <tbody>${modules.map((m) => `<tr class="mod"><th colspan="${ROLES.length + 1}">${h(m)}</th></tr>${M.permissions.filter((p) => p.module === m).map((p) => `<tr>
        <td>${h(p.label)}${p.description ? `<span class="sub">${h(p.description)}</span>` : ""}</td>
        ${ROLES.map((r) => `<td class="c"><input type="checkbox" data-r="${r}" data-p="${p.code}" ${draft[r][p.code] ? "checked" : ""} ${locked(r, p) ? "disabled" : ""} aria-label="${h(ROLE_GR[r])}: ${h(p.label)}" title="${locked(r, p) ? "Σταθερό — δεν αλλάζει από τον πίνακα" : ""}"></td>`).join("")}</tr>`).join("")}`).join("")}
      </tbody></table></div>
    <p class="muted small" style="margin-top:8px">Κλειδωμένα κελιά: η αλλαγή δικαιωμάτων και η ειδική έγκριση υπέρβασης ανήκουν μόνο στη Γενική Διεύθυνση· το περιεχόμενο Exit Interview μόνο σε ΓΔ, HR και εκπαιδευτή· η ΓΔ δεν μπορεί να χάσει τη διαχείριση χρηστών.</p>
    <div class="row-actions" style="margin-top:12px"><input id="pm-note" placeholder="Αιτιολογία αλλαγής (υποχρεωτική)" maxlength="300" style="flex:1;min-width:220px"><span class="muted small" id="pm-n"></span><button class="btn primary" id="pm-save" disabled>Αποθήκευση αλλαγών</button></div>
  </div>
  <div class="card" style="margin-top:16px"><div class="card-head"><h3>Ιστορικό αλλαγών</h3></div>
    ${M.log.length ? `<div class="table-wrap" style="max-height:340px"><table><thead><tr><th>Πότε</th><th>Ποιος</th><th>Ρόλος</th><th>Δικαίωμα</th><th>Αλλαγή</th><th>Αιτιολογία</th></tr></thead><tbody>
      ${M.log.map((l) => `<tr><td class="small">${athens(l.at)}</td><td class="small">${h(l.actor)}</td><td>${ROLE_GR[l.role] || h(l.role)}</td><td class="small">${l.perm ? h(M.permissions.find((p) => p.code === l.perm)?.label || l.perm) : "Πεδίο καταστημάτων"}</td>
        <td class="small">${l.perm ? `${l.old_value === "true" ? "Ναι" : "Όχι"} → <strong>${l.new_value === "true" ? "Ναι" : "Όχι"}</strong>` : `${SCOPE_GR[l.old_value] || h(l.old_value)} → <strong>${SCOPE_GR[l.new_value] || h(l.new_value)}</strong>`}</td><td class="small">${h(l.note || "")}</td></tr>`).join("")}
    </tbody></table></div>` : `<p class="muted">Καμία αλλαγή ακόμη. Ισχύουν οι αρχικές ρυθμίσεις.</p>`}</div>`;
  const upd = () => { const { out, sc } = changes(); const n = out.length + Object.keys(sc).length; $("#pm-n").textContent = n ? `${n} αλλαγές` : ""; $("#pm-save").disabled = !n; };
  $$("[data-r]").forEach((c) => (c.onchange = () => { draft[c.dataset.r][c.dataset.p] = c.checked; c.closest("td").classList.toggle("chg", c.checked !== M.grants[c.dataset.r][c.dataset.p]); upd(); }));
  $$("[data-scope]").forEach((s) => (s.onchange = () => { scopes[s.dataset.scope] = s.value; upd(); }));
  $("#pm-save").onclick = async () => {
    const { out, sc } = changes();
    try { const r = await S.api.permSave(out, sc, $("#pm-note").value.trim()); toast(`Αποθηκεύτηκαν ${r.changed} αλλαγές. Ισχύουν από την επόμενη ενέργεια κάθε χρήστη.`); permissionsView(); }
    catch (e) { toast(e.message, true); }
  };
}
