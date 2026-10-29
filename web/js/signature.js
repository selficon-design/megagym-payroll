// Πεδίο υπογραφής με δάχτυλο, στυλό ή ποντίκι
export function signaturePad(wrap) {
  wrap.innerHTML = `<canvas aria-label="Πεδίο υπογραφής"></canvas><div class="sig-line"></div><div class="sig-hint">Υπογράψτε εδώ</div>`;
  const canvas = wrap.querySelector("canvas");
  const hint = wrap.querySelector(".sig-hint");
  const ctx = canvas.getContext("2d");
  let strokes = 0, length = 0, drawing = false, last = null;

  function resize() {
    const r = canvas.getBoundingClientRect();
    const ratio = Math.max(window.devicePixelRatio || 1, 1.5);
    const data = strokes ? canvas.toDataURL() : null;
    canvas.width = Math.round(r.width * ratio);
    canvas.height = Math.round(r.height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.strokeStyle = "#0e1a2b";
    if (data) { const img = new Image(); img.onload = () => ctx.drawImage(img, 0, 0, r.width, r.height); img.src = data; }
  }
  const pos = (e) => { const r = canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top, p: e.pressure || 0.5 }; };

  canvas.addEventListener("pointerdown", (e) => {
    e.preventDefault(); drawing = true; canvas.setPointerCapture(e.pointerId);
    last = pos(e); strokes++; hint.style.display = "none";
    ctx.beginPath(); ctx.arc(last.x, last.y, 1.2, 0, Math.PI * 2); ctx.fillStyle = "#0e1a2b"; ctx.fill();
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!drawing) return;
    const events = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    for (const ev of events) {
      const p = pos(ev);
      const dist = Math.hypot(p.x - last.x, p.y - last.y);
      ctx.lineWidth = Math.max(1.6, Math.min(3.4, 3.2 - dist * 0.05 + (ev.pointerType === "pen" ? p.p : 0)));
      ctx.beginPath(); ctx.moveTo(last.x, last.y); ctx.lineTo(p.x, p.y); ctx.stroke();
      length += dist; last = p;
    }
  });
  const end = () => { drawing = false; };
  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", end);
  const ro = new ResizeObserver(() => resize());
  ro.observe(canvas);
  resize();

  return {
    isEmpty: () => strokes === 0 || length < 40,
    clear() { ctx.clearRect(0, 0, canvas.width, canvas.height); strokes = 0; length = 0; hint.style.display = ""; },
    /** PNG με λευκό φόντο, περικομμένο γύρω από την υπογραφή */
    toPng() {
      const w = canvas.width, hgt = canvas.height;
      const data = ctx.getImageData(0, 0, w, hgt).data;
      let minX = w, minY = hgt, maxX = 0, maxY = 0;
      for (let y = 0; y < hgt; y += 2) for (let x = 0; x < w; x += 2) {
        if (data[(y * w + x) * 4 + 3] > 20) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
      }
      const pad = 16;
      minX = Math.max(0, minX - pad); minY = Math.max(0, minY - pad); maxX = Math.min(w, maxX + pad); maxY = Math.min(hgt, maxY + pad);
      const cw = Math.max(1, maxX - minX), ch = Math.max(1, maxY - minY);
      const scale = Math.min(1, 900 / cw);
      const out = document.createElement("canvas");
      out.width = Math.round(cw * scale); out.height = Math.round(ch * scale);
      const o = out.getContext("2d");
      o.fillStyle = "#fff"; o.fillRect(0, 0, out.width, out.height);
      o.drawImage(canvas, minX, minY, cw, ch, 0, 0, out.width, out.height);
      return out.toDataURL("image/png");
    },
    destroy() { ro.disconnect(); },
  };
}
