const CACHE = "kikote-gym-v2";
const ASSETS = ["/", "/index.html"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

// Solo se guardan en caché los archivos propios de la app (para abrirla sin
// conexión). Los datos y los vídeos de Supabase van siempre directos a la red:
// así no se llena la memoria del móvil y los vídeos se pueden ir viendo a trozos.
self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  if (new URL(req.url).origin !== self.location.origin) return;
  if (req.headers.has("range")) return;
  e.respondWith(
    fetch(req)
      .then(res => {
        if (res.ok && res.status === 200) { const clone = res.clone(); caches.open(CACHE).then(c => c.put(req, clone)).catch(() => {}); }
        return res;
      })
      .catch(() => caches.match(req))
  );
});
