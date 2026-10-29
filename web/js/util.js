// Βοηθητικά εργαλεία (μορφοποίηση, παράθυρα, μηνύματα, βιβλιοθήκες)

export const $ = (s, el = document) => el.querySelector(s);
export const $$ = (s, el = document) => [...el.querySelectorAll(s)];

export function h(v) {
  return String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

const MONTHS = ["Ιανουάριος", "Φεβρουάριος", "Μάρτιος", "Απρίλιος", "Μάιος", "Ιούνιος", "Ιούλιος", "Αύγουστος", "Σεπτέμβριος", "Οκτώβριος", "Νοέμβριος", "Δεκέμβριος"];
export function monthLabel(m) {
  if (!/^\d{4}-\d{2}$/.test(m || "")) return m || "";
  const [y, mm] = m.split("-");
  return `${MONTHS[Number(mm) - 1]} ${y}`;
}
export function currentMonth() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}
export function shiftMonth(m, delta) {
  const [y, mm] = m.split("-").map(Number);
  const d = new Date(y, mm - 1 + delta, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}
export function monthBounds(m) {
  const [y, mm] = m.split("-").map(Number);
  const first = new Date(y, mm - 1, 1), last = new Date(y, mm, 0);
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  return { first: iso(first), last: iso(last) };
}
export function dmy(iso) {
  if (!iso) return "";
  const s = String(iso).slice(0, 10);
  const [y, m, d] = s.split("-");
  return d && m && y ? `${d}/${m}/${y}` : s;
}
export function defaultPeriod(m) {
  const b = monthBounds(m);
  return `${dmy(b.first)} – ${dmy(b.last)}`;
}
export function dateTime(ts) {
  if (!ts) return "";
  const d = new Date(ts);
  return d.toLocaleString("el-GR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}
export function relTime(ts) {
  const s = (Date.now() - new Date(ts).getTime()) / 1000;
  if (s < 60) return "μόλις τώρα";
  if (s < 3600) return `πριν ${Math.round(s / 60)}′`;
  if (s < 86400) return `πριν ${Math.round(s / 3600)} ώρ.`;
  return dateTime(ts);
}
export function money(n) {
  if (n === null || n === undefined || n === "") return "—";
  return Number(n).toLocaleString("el-GR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
}
/** "1.250,50" / "1250.5" / 1250.5 → 1250.5 (ή null) */
export function parseAmount(v) {
  if (typeof v === "number") return isFinite(v) && v >= 0 ? Math.round(v * 100) / 100 : null;
  let s = String(v ?? "").trim().replace(/\s|€/g, "");
  if (!s) return null;
  if (/^\d+\.\d{1,2}$/.test(s)) return Number(s);
  s = s.replace(/\./g, "").replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const n = Number(s);
  return n >= 0 && n < 1000000 ? n : null;
}
export function amountText(n) {
  return Number(n).toLocaleString("el-GR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
export function initials(name) {
  return String(name || "?").split(/\s+/).filter(Boolean).slice(0, 2).map((x) => x[0]).join("").toUpperCase();
}
export function norm(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}

/** Το κείμενο της δήλωσης — ίδιο με αυτό που αποθηκεύει η βάση. */
export function statementText(company, endDateIso, period, amount) {
  return `Δηλώνω υπεύθυνα ότι από την ημερομηνία έναρξης της απασχόλησής μου στην εταιρεία ${company} και έως την ${dmy(endDateIso)}, έχω λάβει όλες τις δεδουλευμένες αποδοχές μου, καθώς και οποιαδήποτε επιπρόσθετη οικονομική απαίτηση που ενδεχομένως υπήρχε (όπως αναρρωτική άδεια, υπερωριακή απασχόληση, νόμιμη άδεια κ.λπ.), πλήρως και χωρίς καμία εκκρεμότητα.

Πραγματοποιήθηκε ανάλυση των ποσών που αντιστοιχούν στο χρονικό διάστημα ${period}, ποσό: ${amountText(amount)}€, από το Τμήμα Ανθρώπινου Δυναμικού της επιχείρησης, έγινε αποδεκτή από εμένα, έχουν ήδη κατατεθεί στον τραπεζικό μου λογαριασμό και ουδεμία άλλη απαίτηση έχω.

Επιπλέον του μισθού μου, δηλώνω ότι έχω λάβει όλες τις πρόσθετες παροχές που δικαιούμαι σε μορφή διατακτικών, δωροκάρτας ή και των δύο.`;
}

export const STATUS = {
  signed: { label: "Υπογεγραμμένη", cls: "b-signed" },
  pending: { label: "Προς υπογραφή", cls: "b-pending" },
  missing: { label: "Χωρίς δήλωση", cls: "b-missing" },
  voided: { label: "Ακυρωμένη", cls: "b-voided" },
};
export const badge = (s) => `<span class="badge ${STATUS[s]?.cls || ""}">${STATUS[s]?.label || h(s)}</span>`;
export const ROLE_GR = { owner: "Ιδιοκτήτρια", hr: "HR", manager: "Manager" };

// ── Μηνύματα ──
let toastTimer;
export function toast(msg, isErr = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.toggle("err", !!isErr);
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), isErr ? 5200 : 3000);
}

// ── Παράθυρα ──
export function openDialog(html, { onOpen, wide } = {}) {
  const d = $("#dlg");
  $("#dlg-body").innerHTML = `<div class="dlg-inner">${html}</div>`;
  d.style.width = wide ? "min(980px,calc(100% - 24px))" : "";
  if (!d.open) d.showModal();
  d.querySelectorAll("[data-close]").forEach((b) => (b.onclick = () => d.close()));
  onOpen?.(d);
  return d;
}
export function closeDialog() {
  const d = $("#dlg");
  if (d.open) d.close();
}
export function confirmBox(title, text, { ok = "Επιβεβαίωση", danger = false, input = null } = {}) {
  return new Promise((resolve) => {
    openDialog(
      `<div class="dlg-head"><h2>${h(title)}</h2></div><p class="muted">${h(text)}</p>
       ${input ? `<label>${h(input)}</label><input id="cb-input" maxlength="300">` : ""}
       <div class="dlg-foot"><button class="btn" data-close>Άκυρο</button><button class="btn ${danger ? "danger" : "primary"}" id="cb-ok">${h(ok)}</button></div>`,
      {
        onOpen(d) {
          let done = false;
          d.addEventListener("close", () => { if (!done) resolve(null); }, { once: true });
          $("#cb-ok").onclick = () => {
            const v = input ? $("#cb-input").value.trim() : true;
            if (input && v.length < 3) { $("#cb-input").focus(); return; }
            done = true; d.close(); resolve(v);
          };
          if (input) $("#cb-input").focus();
        },
      }
    );
  });
}

// ── Βιβλιοθήκες κατ' απαίτηση ──
const loaded = {};
export function loadScript(src) {
  return (loaded[src] ??= new Promise((res, rej) => {
    const s = document.createElement("script");
    s.src = src; s.onload = res; s.onerror = () => rej(new Error("Δεν φορτώθηκε το " + src));
    document.head.append(s);
  }));
}
export async function xlsx() { await loadScript("vendor/xlsx.js"); return window.XLSX; }

export async function downloadXlsx(filename, sheets) {
  const X = await xlsx();
  const wb = X.utils.book_new();
  for (const [name, rows] of Object.entries(sheets)) {
    const ws = X.utils.aoa_to_sheet(rows);
    ws["!cols"] = (rows[0] || []).map((_, i) => ({ wch: Math.min(48, Math.max(10, ...rows.map((r) => String(r[i] ?? "").length + 2))) }));
    X.utils.book_append_sheet(wb, ws, name.slice(0, 31));
  }
  X.writeFile(wb, filename);
}
export async function readXlsx(file) {
  const X = await xlsx();
  const wb = X.read(await file.arrayBuffer(), { type: "array", cellText: true });
  return { wb, X, sheet: (name) => (wb.Sheets[name] ? X.utils.sheet_to_json(wb.Sheets[name], { header: 1, raw: false, defval: "" }) : null) };
}
export function saveBlob(blob, filename) {
  const a = document.createElement("a");
  const url = URL.createObjectURL(blob);
  a.href = url; a.download = filename;
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}
export function safeName(s) {
  return String(s).replace(/[\\/:*?"<>|]+/g, "_").replace(/\s+/g, "_").slice(0, 80);
}
