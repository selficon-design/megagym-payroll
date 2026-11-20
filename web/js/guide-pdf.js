// PDF του Οδηγού χρήσης (στον browser, ίδιες βιβλιοθήκες με τις δηλώσεις). Δεν περιέχει δεδομένα,
// οπότε διατίθεται σε όλους τους ρόλους. Φτιάχνεται κάθε φορά από το τρέχον web/guide.md.
import { loadScript, saveBlob } from "./util.js";

// Μπλοκ του markdown που χρησιμοποιεί ο οδηγός
export function parseBlocks(md) {
  const lines = md.replace(/<!--[\s\S]*?-->\n?/g, "").split("\n");
  const out = [];
  const isTable = (l) => /^\|.*\|\s*$/.test(l);
  const clean = (t) => t.replace(/\*\*([^*]+)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1").replace(/\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/g, "$1 ($2)");
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    let m;
    if ((m = l.match(/^(#{1,4})\s+(.*)$/))) { out.push({ t: "h" + m[1].length, text: clean(m[2]) }); i++; continue; }
    if (isTable(l)) {
      const rows = [];
      while (i < lines.length && isTable(lines[i])) { rows.push(lines[i]); i++; }
      const cells = (r) => r.trim().replace(/^\||\|$/g, "").split("|").map((c) => clean(c.trim()));
      out.push({ t: "table", head: cells(rows[0]), rows: rows.slice(2).map(cells) });
      continue;
    }
    if ((m = l.match(/^(\s*)([-*]|\d+\.)\s+(.*)$/))) {
      const level = Math.floor(m[1].length / 2) > 0 ? 1 : 0;
      out.push({ t: "li", level, marker: /\d/.test(m[2]) ? m[2] : "•", text: clean(m[3]) });
      i++; continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^#{1,4}\s/.test(lines[i]) && !isTable(lines[i]) && !/^\s*([-*]|\d+\.)\s+/.test(lines[i])) { para.push(lines[i].trim()); i++; }
    out.push({ t: "p", text: clean(para.join(" ")) });
  }
  return out;
}

export async function guidePdf(md, version) {
  await Promise.all([loadScript("vendor/pdf-lib.js"), loadScript("vendor/fontkit.js")]);
  const [fontBytes, logoBytes] = await Promise.all([
    fetch("vendor/DejaVuSans.ttf").then((r) => r.arrayBuffer()),
    fetch("mega-gym-logo.png").then((r) => r.arrayBuffer()),
  ]);
  const { PDFDocument, rgb } = window.PDFLib;
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(window.fontkit);
  pdf.setTitle(`Οδηγός χρήσης MEGA GYM ${version}`);
  pdf.setAuthor("MEGA GYM");
  const font = await pdf.embedFont(fontBytes, { subset: true });
  const logo = await pdf.embedPng(logoBytes);
  const has = new Set(font.getCharacterSet());
  // Σύμβολα που δεν έχει η γραμματοσειρά (emoji): λέξη ή τίποτα, ώστε να μη βγαίνουν κουτάκια
  const SUB = { "🔒": "[σταθερό]", "🎤": "", "🔊": "", "✦": "", "⇩": "", "⇧": "", "▣": "", "⚙": "", "↺": "", "⚠": "!" };
  const safe = (s) => [...String(s)].map((c) => (c in SUB ? SUB[c] : has.has(c.codePointAt(0)) ? c : "")).join("").replace(/ {2,}/g, " ").trim();

  const W = 595, H = 842, M = 50, maxW = W - 2 * M, BOTTOM = 60;
  const ink = rgb(0.07, 0.09, 0.11), muted = rgb(0.42, 0.46, 0.51), line = rgb(0.86, 0.88, 0.9), gold = rgb(0.85, 0.62, 0), head = rgb(0.96, 0.96, 0.97);
  let page, y;
  const newPage = () => { page = pdf.addPage([W, H]); y = H - M; };
  const need = (h) => { if (y - h < BOTTOM) newPage(); };
  const wrap = (text, size, width) => {
    const out = [];
    for (const para of safe(text).split("\n")) {
      let cur = "";
      for (const w of para.split(" ")) {
        const cand = cur ? cur + " " + w : w;
        if (font.widthOfTextAtSize(cand, size) > width && cur) { out.push(cur); cur = w; } else cur = cand;
      }
      out.push(cur);
    }
    return out;
  };
  const write = (text, { size = 10.5, x = M, width = maxW, color = ink, lead = size * 1.45, gap = 4 } = {}) => {
    for (const l of wrap(text, size, width)) { need(lead); page.drawText(l, { x, y: y - size, size, font, color }); y -= lead; }
    y -= gap;
  };

  // Εξώφυλλο / κεφαλίδα
  const blocks = parseBlocks(md);
  newPage();
  page.drawRectangle({ x: 0, y: H - 90, width: W, height: 90, color: rgb(0, 0, 0) });
  const lw = 200, lh = (logo.height / logo.width) * lw;
  page.drawImage(logo, { x: M - 6, y: H - 45 - lh / 2, width: lw, height: lh });
  const tag = "ΟΔΗΓΟΣ ΧΡΗΣΗΣ";
  page.drawText(tag, { x: W - M - font.widthOfTextAtSize(tag, 13), y: H - 42, size: 13, font, color: rgb(1, 0.77, 0) });
  const vtxt = safe(`Έκδοση ${version}`);
  page.drawText(vtxt, { x: W - M - font.widthOfTextAtSize(vtxt, 10), y: H - 60, size: 10, font, color: rgb(0.8, 0.82, 0.85) });
  y = H - 120;
  const title = blocks.find((b) => b.t === "h1");
  if (title) write(title.text, { size: 18, gap: 10 });

  // Περιεχόμενα
  write("Περιεχόμενα", { size: 13, color: gold, gap: 2 });
  for (const b of blocks.filter((b) => b.t === "h2")) write(b.text, { size: 10.5, x: M + 10, width: maxW - 10, gap: 0 });
  y -= 10;

  for (const b of blocks) {
    if (b.t === "h1") continue;
    if (b.t === "h2") { need(80); y -= 10; page.drawLine({ start: { x: M, y }, end: { x: W - M, y }, thickness: 1, color: line }); y -= 8; write(b.text, { size: 15, gap: 6 }); }
    else if (b.t === "h3" || b.t === "h4") { need(50); y -= 4; write(b.text, { size: 12, color: gold, gap: 3 }); }
    else if (b.t === "p") write(b.text);
    else if (b.t === "li") {
      const ind = M + 12 + b.level * 18, mw = font.widthOfTextAtSize(b.marker, 10.5) + 6;
      const ls = wrap(b.text, 10.5, maxW - (ind - M) - mw);
      ls.forEach((l, k) => { need(15); if (!k) page.drawText(safe(b.marker), { x: ind, y: y - 10.5, size: 10.5, font, color: muted }); page.drawText(l, { x: ind + mw, y: y - 10.5, size: 10.5, font, color: ink }); y -= 15; });
      y -= 2;
    } else if (b.t === "table") {
      const n = b.head.length, size = 9, lead = 12.5, pad = 4;
      // Πλάτη στηλών ανάλογα με το μήκος του περιεχομένου (με ελάχιστο)
      const len = b.head.map((_, c) => Math.max(...[b.head, ...b.rows].map((r) => Math.min(60, (r[c] || "").length)), 4));
      const tot = len.reduce((a, v) => a + v, 0);
      const ws = len.map((v) => Math.max(48, (v / tot) * maxW));
      const k = maxW / ws.reduce((a, v) => a + v, 0); for (let c = 0; c < n; c++) ws[c] *= k;
      const drawRow = (cells, isHead) => {
        const wrapped = cells.map((t, c) => wrap(t || "", size, ws[c] - 2 * pad));
        const h = Math.max(...wrapped.map((w) => w.length)) * lead + 2 * pad;
        if (y - h < BOTTOM) { newPage(); if (!isHead) drawRow(b.head, true); }
        if (isHead) page.drawRectangle({ x: M, y: y - h, width: maxW, height: h, color: head });
        let x = M;
        wrapped.forEach((ls, c) => { ls.forEach((l, j) => page.drawText(l, { x: x + pad, y: y - pad - size - j * lead, size, font, color: isHead ? muted : ink })); x += ws[c]; });
        page.drawLine({ start: { x: M, y: y - h }, end: { x: W - M, y: y - h }, thickness: 0.6, color: line });
        y -= h;
      };
      need(40); drawRow(b.head, true); b.rows.forEach((r) => drawRow(r, false)); y -= 8;
    }
  }

  // Αριθμός σελίδας
  const pages = pdf.getPages();
  pages.forEach((p, i) => {
    const t = safe(`Οδηγός χρήσης MEGA GYM · έκδοση ${version} · σελίδα ${i + 1} / ${pages.length}`);
    p.drawText(t, { x: (W - font.widthOfTextAtSize(t, 8)) / 2, y: 28, size: 8, font, color: muted });
  });
  const bytes = await pdf.save();
  const name = `Οδηγός χρήσης MEGA GYM ${String(version).split(" ")[0]}.pdf`;
  saveBlob(new Blob([bytes], { type: "application/pdf" }), name);
  return { pages: pages.length, name };
}
