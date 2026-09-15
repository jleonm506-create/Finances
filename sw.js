// Service worker — Sobres
// Cachea el shell de la app para que abra sin internet.
// Los datos NO pasan por aquí: viven en localStorage del navegador.
const VERSION = 'sobres-v5';
const SHELL = ['./', './index.html', './config.js', './manifest.json', './icons/icono-192.png', './icons/icono-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // Fuentes de Google: guardar la primera vez, servir de caché después.
  if (url.hostname.endsWith('googleapis.com') || url.hostname.endsWith('gstatic.com') || url.hostname === 'cdn.jsdelivr.net') {
    e.respondWith(caches.open(VERSION).then(async c => {
      const hit = await c.match(e.request);
      const red = fetch(e.request).then(r => { if (r.ok) c.put(e.request, r.clone()); return r; }).catch(() => hit);
      return hit || red;
    }));
    return;
  }
  // Shell: caché primero, red como respaldo.
  if (e.request.mode === 'navigate' || SHELL.some(p => url.pathname.endsWith(p.replace('./', '/')))) {
    e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(hit => hit || fetch(e.request)));
  }
});
