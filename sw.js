// Service worker: hace que la app abra rápido y se pueda instalar.
// Los DATOS (Supabase) nunca se guardan en caché: siempre se piden frescos.
// Si cambias index.html no hace falta tocar nada; sube VERSION solo si cambias íconos o el manifest.
const VERSION = "inv-v1";
const SHELL = ["./", "./index.html", "./config.js", "./manifest.webmanifest",
  "./icons/icon-192.png", "./icons/icon-512.png", "./icons/apple-touch-icon.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // Librería de Supabase (versión fija en el CDN): caché primero
  if (url.hostname === "cdn.jsdelivr.net") {
    e.respondWith(caches.match(req).then(r => r || fetch(req).then(res => {
      const copia = res.clone(); caches.open(VERSION).then(c => c.put(req, copia)); return res;
    })));
    return;
  }

  // Archivos de la propia app: red primero (siempre la última versión), caché si no hay internet
  if (url.origin === self.location.origin) {
    e.respondWith(fetch(req).then(res => {
      if (res.ok) { const copia = res.clone(); caches.open(VERSION).then(c => c.put(req, copia)); }
      return res;
    }).catch(() => caches.match(req, { ignoreSearch: true }).then(r => r || caches.match("./index.html"))));
  }
  // Todo lo demás (API de Supabase, fotos) pasa directo a la red
});
