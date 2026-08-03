const CACHE = "aponta-horas-v2.19.4";
const ASSETS = [
  "./",
  "./index.html",
  "./app-v2.19.4.js?build=2194",
  "./style-v2.19.4.css?build=2194",
  "./redefinir-senha.html",
  "./auth-recovery-v2.19.4.js?build=2194",
  "./manifest.webmanifest?v=2.19.4",
  "./modular-app-icon-192-v2116.png",
  "./modular-app-icon-512-v2116.png"
];

self.addEventListener("install", event => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(ASSETS))
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key !== CACHE).map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") return;

  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  if (event.request.mode === "navigate") {
    const isRecovery =
      url.pathname.endsWith("/redefinir-senha") ||
      url.pathname.endsWith("/redefinir-senha/") ||
      url.pathname.endsWith("/redefinir-senha.html");

    const fallback = isRecovery
      ? "./redefinir-senha.html"
      : "./index.html";

    event.respondWith(
      fetch(event.request)
        .then(response => {
          if(response.ok){
            const copy=response.clone();
            caches.open(CACHE).then(cache => cache.put(fallback,copy));
          }
          return response;
        })
        .catch(() => caches.match(fallback))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then(cached => {
      const network=fetch(event.request)
        .then(response => {
          if(response.ok){
            const copy=response.clone();
            caches.open(CACHE).then(cache => cache.put(event.request,copy));
          }
          return response;
        })
        .catch(() => cached);

      return cached || network;
    })
  );
});
