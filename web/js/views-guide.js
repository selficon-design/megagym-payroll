// Οδηγός χρήσης μέσα στην εφαρμογή. Το κείμενο είναι το web/guide.md, που δημοσιεύεται με κάθε έκδοση,
// οπότε ο οδηγός είναι πάντα αυτός της τρέχουσας έκδοσης. Ορατός σε όλους τους ρόλους (δεν περιέχει δεδομένα).
import { $, $$, h, toast } from "./util.js";
import { APP_VERSION } from "./version.js";

const view = () => $("#view");
let cache = null;

// Μικρός μετατροπέας markdown για όσα χρησιμοποιεί ο οδηγός: επικεφαλίδες, παράγραφοι, λίστες (και εμφωλευμένες),
// πίνακες, έντονα, `κώδικας`, [σύνδεσμοι](https://…). Όλο το κείμενο περνά από escape πριν μορφοποιηθεί.
function inline(t) {
  let s = h(t);
  s = s.replace(/`([^`]+)`/g, "<code>$1</code>");
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/g, (_, a, u) => `<a href="${u}" target="_blank" rel="noopener">${a}</a>`);
  return s;
}
const slug = (t, i) => "g-" + i;

export function renderMarkdown(md) {
  const lines = md.replace(/<!--[\s\S]*?-->\n?/g, "").split("\n");
  const out = [], toc = [];
  let i = 0, sec = 0;
  const isTable = (l) => /^\|.*\|\s*$/.test(l);
  const isItem = (l) => /^(\s*)([-*]|\d+\.)\s+/.test(l);
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    let m;
    if ((m = l.match(/^(#{1,4})\s+(.*)$/))) {
      const lvl = m[1].length, txt = m[2];
      if (lvl === 1) { i++; continue; } // ο τίτλος μπαίνει στην κεφαλίδα της σελίδας
      if (lvl === 2) { sec++; toc.push({ id: slug(txt, sec), txt }); out.push(`</section><section class="g-sec" id="${slug(txt, sec)}"><h2>${inline(txt)}</h2>`); }
      else out.push(`<h${lvl}>${inline(txt)}</h${lvl}>`);
      i++; continue;
    }
    if (isTable(l)) {
      const rows = [];
      while (i < lines.length && isTable(lines[i])) { rows.push(lines[i]); i++; }
      const cells = (r) => r.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
      const head = cells(rows[0]), body = rows.slice(2).map(cells);
      out.push(`<div class="table-wrap"><table><thead><tr>${head.map((c) => `<th>${inline(c)}</th>`).join("")}</tr></thead><tbody>${body.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`);
      continue;
    }
    if (isItem(l)) {
      // Λίστα με εμφώλευση βάσει εσοχής
      const stack = [];
      const open = (ind, ord) => { out.push(ord ? "<ol>" : "<ul>"); stack.push({ ind, ord }); };
      while (i < lines.length && (isItem(lines[i]) || (lines[i].trim() && /^\s{2,}/.test(lines[i])))) {
        const li = lines[i];
        const mm = li.match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);
        if (!mm) { out.push(" " + inline(li.trim())); i++; continue; }
        const ind = mm[1].length, ord = /\d/.test(mm[2]);
        if (!stack.length || ind > stack.at(-1).ind) open(ind, ord);
        else {
          out.push("</li>");
          while (stack.length && ind < stack.at(-1).ind) { out.push(stack.pop().ord ? "</ol>" : "</ul>"); out.push("</li>"); }
        }
        out.push(`<li>${inline(mm[3])}`);
        i++;
      }
      while (stack.length) { out.push("</li>"); out.push(stack.pop().ord ? "</ol>" : "</ul>"); }
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^#{1,4}\s/.test(lines[i]) && !isTable(lines[i]) && !isItem(lines[i])) { para.push(lines[i].trim()); i++; }
    out.push(`<p>${inline(para.join(" "))}</p>`);
  }
  const html = `<section class="g-sec">${out.join("")}</section>`.replace(/<section class="g-sec"><\/section>/g, "");
  return { html, toc };
}

export async function guide() {
  view().innerHTML = `<div class="empty"><div class="spinner"></div></div>`;
  try {
    if (!cache) {
      const r = await fetch(`guide.md?v=${encodeURIComponent(APP_VERSION)}`, { cache: "no-cache" });
      if (!r.ok) throw new Error(r.status);
      cache = await r.text();
    }
  } catch { return (view().innerHTML = `<div class="card empty">Ο οδηγός δεν φόρτωσε. Ελέγξτε τη σύνδεση και δοκιμάστε ξανά.</div>`); }
  const ver = (cache.match(/GUIDE_VERSION:\s*([^\n]*?)\s*-->/) || [])[1] || APP_VERSION;
  const { html, toc } = renderMarkdown(cache);
  view().innerHTML = `
  <div class="page-head"><div><div class="eyebrow">Βοήθεια</div><h1>Οδηγός χρήσης</h1>
    <p class="muted">Έκδοση ${h(ver)}. Ενημερώνεται αυτόματα με κάθε νέα έκδοση της εφαρμογής.</p></div>
    <div class="row-actions"><button class="btn primary" id="g-pdf">⇩ PDF</button><button class="btn" id="g-print">Εκτύπωση</button></div></div>
  <div class="card g-tools"><input id="g-q" type="search" placeholder="Αναζήτηση στον οδηγό (π.χ. άδεια, PDF, πρόγραμμα)…" aria-label="Αναζήτηση στον οδηγό">
    <nav class="g-toc" aria-label="Περιεχόμενα">${toc.map((t) => `<a href="#" data-g="${t.id}">${inline(t.txt)}</a>`).join("")}</nav></div>
  <div class="card guide" id="g-body">${html}</div>
  <p class="muted small" id="g-none" hidden>Δεν βρέθηκε κάτι. Δοκιμάστε άλλη λέξη.</p>`;
  $$("[data-g]").forEach((a) => (a.onclick = (e) => { e.preventDefault(); document.getElementById(a.dataset.g)?.scrollIntoView({ behavior: "smooth", block: "start" }); }));
  $("#g-print").onclick = () => window.print();
  $("#g-pdf").onclick = async (e) => {
    const b = e.currentTarget; b.disabled = true; b.textContent = "Δημιουργία PDF…";
    try { const { guidePdf } = await import("./guide-pdf.js"); const r = await guidePdf(cache, ver); toast(`Το PDF κατέβηκε (${r.pages} σελίδες).`); }
    catch (err) { toast("Το PDF δεν δημιουργήθηκε: " + (err.message || err), true); }
    finally { if (b.isConnected) { b.disabled = false; b.textContent = "⇩ PDF"; } }
  };
  const norm = (s) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  $("#g-q").oninput = (e) => {
    const q = norm(e.target.value.trim());
    let shown = 0;
    $$("#g-body .g-sec").forEach((s) => { const ok = !q || norm(s.textContent).includes(q); s.hidden = !ok; shown += ok; });
    $("#g-none").hidden = shown > 0;
  };
}
