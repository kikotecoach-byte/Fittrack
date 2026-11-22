const CACHE = "kikote-gym-v3";
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

// ── Avisos push (p. ej. «Luis ha terminado su entreno») ──
// Llegan aunque la app esté cerrada. Si está abierta, además se le pasa el
// aviso para que se actualice al momento.
self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: "Kikote Gym", body: e.data ? e.data.text() : "" }; }
  const opts = { body: d.body || "", icon: "/icon-192.png", badge: "/favicon-32.png", vibrate: [120, 60, 120], data: { url: d.url || "/" } };
  if (d.tag) { opts.tag = d.tag; opts.renotify = true; }
  e.waitUntil((async () => {
    await self.registration.showNotification(d.title || "Kikote Gym", opts);
    const cs = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    cs.forEach(c => c.postMessage({ type: "kk-push", data: d }));
  })());
});

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || "/";
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(cs => {
    for (const c of cs) if ("focus" in c) return c.focus();
    return self.clients.openWindow(url);
  }));
});
