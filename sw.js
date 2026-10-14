// Workout Gang service worker: lets the site install as an app and open when offline.
// Always asks the network first, so updates show up right away; the saved copy is only a fallback.
const CACHE = "workout-gang-v1";
const SHELL = ["./", "./index.html", "./config.js", "./manifest.json", "./img/icon-192.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET") return;
  // The database library is a fixed version, so a saved copy never goes stale: use it straight away.
  if (url.host === "cdn.jsdelivr.net" && /@\d+\.\d+\.\d+\//.test(url.pathname)) {
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); }
      return res;
    })));
    return;
  }
  // Otherwise only this site's own files. Database, sign-in and fonts go straight to the network.
  if (url.origin !== location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request.mode === "navigate" ? "./" : e.request, copy)); }
        return res;
      })
      .catch(() => caches.match(e.request.mode === "navigate" ? "./" : e.request).then(r => r || caches.match("./")))
  );
});
