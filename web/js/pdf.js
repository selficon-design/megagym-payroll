// Δημιουργία PDF δηλώσεων (στον browser) και ZIP μηνιαίου backup
import { loadScript, monthLabel, money, dateTime, dmy, safeName, saveBlob } from "./util.js";

let assets;
async function load() {
  await Promise.all([loadScript("vendor/pdf-lib.js"), loadScript("vendor/fontkit.js")]);
  assets ??= Promise.all([
    fetch("vendor/DejaVuSans.ttf").then((r) => r.arrayBuffer()),
    fetch("mega-gym-logo.png").then((r) => r.arrayBuffer()),
  ]);
  return assets;
}

export async function declarationPdf(d) {
  const [fontBytes, logoBytes] = await load();
  const { PDFDocument, rgb } = window.PDFLib;
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(window.fontkit);
  pdf.setTitle(`Δήλωση ${d.employee_name} ${d.month}`);
  pdf.setAuthor("MEGA GYM");
  const font = await pdf.embedFont(fontBytes, { subset: true });
  const logo = await pdf.embedPng(logoBytes);
  const W = 595, H = 842, M = 48;
  let page = pdf.addPage([W, H]);
  const ink = rgb(0.07, 0.09, 0.11), muted = rgb(0.42, 0.46, 0.51), line = rgb(0.88, 0.9, 0.92);

  // Κεφαλίδα
  page.drawRectangle({ x: 0, y: H - 86, width: W, height: 86, color: rgb(0, 0, 0) });
  const lw = 210, lh = (logo.height / logo.width) * lw;
  page.drawImage(logo, { x: M - 6, y: H - 43 - lh / 2, width: lw, height: lh });
  page.drawText("ΔΗΛΩΣΗ ΕΡΓΑΖΟΜΕΝΟΥ", { x: W - M - font.widthOfTextAtSize("ΔΗΛΩΣΗ ΕΡΓΑΖΟΜΕΝΟΥ", 13), y: H - 40, size: 13, font, color: rgb(1, 0.77, 0) });
  const sub = monthLabel(d.month);
  page.drawText(sub, { x: W - M - font.widthOfTextAtSize(sub, 10), y: H - 58, size: 10, font, color: rgb(0.8, 0.82, 0.85) });

  let y = H - 120;
  const field = (label, value, x, w) => {
    page.drawText(label, { x, y, size: 8.5, font, color: muted });
    let v = String(value ?? "");
    while (v.length > 3 && font.widthOfTextAtSize(v, 11) > w - 6) v = v.slice(0, -2);
    page.drawText(v, { x, y: y - 15, size: 11, font, color: ink });
  };
  const col = (W - 2 * M) / 3;
  field("Εργαζόμενος", d.employee_name, M, col * 1.4); field("Κωδικός", d.employee_code, M + col * 1.4, col * 0.8); field("Μήνας", monthLabel(d.month), M + col * 2.2, col * 0.8);
  y -= 40;
  field("Κατάστημα", d.store, M, col * 1.4); field("Εταιρεία", d.company, M + col * 1.4, col * 1.6);
  y -= 40;
  field("Χρονικό διάστημα", d.period, M, col * 1.4); field("Έως", dmy(d.end_date), M + col * 1.4, col * 0.8); field("Ποσό", money(d.amount), M + col * 2.2, col * 0.8);
  y -= 30;
  page.drawLine({ start: { x: M, y }, end: { x: W - M, y }, thickness: 1, color: line });
  y -= 26;

  const size = 11, lead = 17, maxW = W - 2 * M;
  const text = d.statement || "";
  for (const para of text.split("\n")) {
    if (!para.trim()) { y -= 6; continue; }
    let cur = "";
    for (const w of para.split(" ")) {
      const cand = cur ? cur + " " + w : w;
      if (font.widthOfTextAtSize(cand, size) > maxW && cur) {
        if (y < 200) { page = pdf.addPage([W, H]); y = H - M; }
        page.drawText(cur, { x: M, y, size, font, color: ink }); y -= lead; cur = w;
      } else cur = cand;
    }
    if (cur) { page.drawText(cur, { x: M, y, size, font, color: ink }); y -= lead; }
  }

  // Υπογραφή
  if (y < 230) { page = pdf.addPage([W, H]); y = H - M; }
  y -= 18;
  page.drawText("Ο/Η Δηλών/ούσα", { x: M, y, size: 9, font, color: muted });
  y -= 8;
  if (d.signature) {
    const sig = await pdf.embedPng(d.signature);
    const r = Math.min(260 / sig.width, 100 / sig.height);
    const sw = sig.width * r, sh = sig.height * r;
    page.drawImage(sig, { x: M, y: y - sh, width: sw, height: sh });
    y -= sh + 6;
  }
  page.drawLine({ start: { x: M, y }, end: { x: M + 260, y }, thickness: 0.8, color: muted });
  y -= 15;
  page.drawText(d.signer || "", { x: M, y, size: 11, font, color: ink });
  y -= 15;
  if (d.signed_at) page.drawText("Υπογράφηκε: " + dateTime(d.signed_at), { x: M, y, size: 9, font, color: muted });

  // Υποσέλιδο
  const foot = `Αρ. δήλωσης ${d.id} · Ηλεκτρονική υπογραφή σε συσκευή καταστήματος${d.signed_by ? " · λογαριασμός " + d.signed_by : ""}`;
  pdf.getPages().forEach((p, i, all) => {
    p.drawLine({ start: { x: M, y: 42 }, end: { x: W - M, y: 42 }, thickness: 0.6, color: line });
    let f = foot;
    while (font.widthOfTextAtSize(f, 7.5) > W - 2 * M - 30) f = f.slice(0, -2);
    p.drawText(f === foot ? f : f + "…", { x: M, y: 28, size: 7.5, font, color: muted });
    p.drawText(`${i + 1}/${all.length}`, { x: W - M - 16, y: 28, size: 7.5, font, color: muted });
  });
  return pdf.save();
}

export async function downloadDeclarationPdf(d) {
  const bytes = await declarationPdf(d);
  saveBlob(new Blob([bytes], { type: "application/pdf" }), `${safeName(d.employee_name)}_${d.month}.pdf`);
}

/** ZIP με PDF ανά κατάστημα + Excel σύνοψη */
export async function backupZip(month, decls, onProgress) {
  await loadScript("vendor/jszip.js");
  const zip = new window.JSZip();
  const summary = [["Κατάστημα", "Κωδικός", "Εργαζόμενος", "Εταιρεία", "Μήνας", "Διάστημα", "Ποσό", "Υπογράφων", "Ημ/νία υπογραφής", "Αρ. δήλωσης"]];
  let i = 0;
  for (const d of decls) {
    const bytes = await declarationPdf(d);
    zip.file(`${safeName(d.store)}/${safeName(d.employee_code)}_${safeName(d.employee_name)}.pdf`, bytes);
    summary.push([d.store, d.employee_code, d.employee_name, d.company, d.month, d.period, Number(d.amount), d.signer, dateTime(d.signed_at), d.id]);
    onProgress?.(++i, decls.length);
  }
  const X = window.XLSX || (await import("./util.js").then((m) => m.xlsx()));
  const wb = X.utils.book_new();
  X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet(summary), "Σύνοψη");
  zip.file(`Σύνοψη_${month}.xlsx`, X.write(wb, { type: "array", bookType: "xlsx" }));
  const blob = await zip.generateAsync({ type: "blob", compression: "DEFLATE" });
  saveBlob(blob, `MEGA_GYM_Δηλώσεις_${month}.zip`);
}
