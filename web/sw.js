// Service worker: γρήγορο άνοιγμα και λειτουργία της οθόνης χωρίς σύνδεση.
// Τα δεδομένα (Supabase) δεν αποθηκεύονται ποτέ εδώ.
const VERSION = "mg-payroll-__BUILD__";
const SHELL = [
  "./", "index.html", "styles.css", "config.js", "manifest.webmanifest", "mega-gym-logo.png",
  "js/app.js", "js/core.js", "js/util.js", "js/views-main.js", "js/views-more.js", "js/signature.js", "js/pdf.js",
  "js/api-supabase.js", "js/api-demo.js", "icons/icon-192.png", "icons/favicon-64.png",
  "js/hr-common.js", "js/fill-launch.js", "js/fill.js", "js/views-hr.js", "js/views-card.js", "js/views-stats.js",
  "js/views-assess.js", "js/views-admin.js", "js/stats-calc.js",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;
  // Βιβλιοθήκες: πρώτα από την cache. Όλα τα υπόλοιπα: πρώτα από το δίκτυο.
  if (url.pathname.includes("/vendor/")) {
    e.respondWith(caches.match(e.request).then((hit) => hit || fetch(e.request).then((r) => { const copy = r.clone(); caches.open(VERSION).then((c) => c.put(e.request, copy)); return r; })));
    return;
  }
  e.respondWith(
    fetch(e.request).then((r) => { if (r.ok) { const copy = r.clone(); caches.open(VERSION).then((c) => c.put(e.request, copy)); } return r; })
      .catch(() => caches.match(e.request).then((hit) => hit || caches.match("index.html")))
  );
});
