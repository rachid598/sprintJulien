// Service worker : application utilisable hors ligne, au bord de la piste.
// Incrémenter VERSION à chaque publication pour renouveler le cache.
const VERSION = 'sprinttimer-v1';
const ASSETS = [
  './',
  'index.html',
  'manifest.webmanifest',
  'css/app.css',
  'icons/apple-touch-icon.png',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/maskable-512.png',
  'js/app.js',
  'js/audio-worklet.js',
  'js/raceController.js',
  'js/core/frameTimeline.js',
  'js/core/models.js',
  'js/core/motion.js',
  'js/core/pdf.js',
  'js/core/results.js',
  'js/core/timing.js',
  'js/services/camera.js',
  'js/services/exporter.js',
  'js/services/signals.js',
  'js/services/storage.js',
  'js/vendor/capacitor-core.js',
  'js/vendor/preact-htm.js',
  'js/views/analysis.js',
  'js/views/common.js',
  'js/views/home.js',
  'js/views/newRace.js',
  'js/views/raceScreen.js',
  'js/views/results.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// Cache d'abord (démarrage instantané hors ligne), mise à jour en arrière-plan.
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  event.respondWith(
    caches.open(VERSION).then(async (cache) => {
      const cached = await cache.match(req, { ignoreSearch: true });
      const network = fetch(req).then((res) => {
        if (res.ok && res.type === 'basic') cache.put(req, res.clone());
        return res;
      }).catch(() => null);
      if (cached) { event.waitUntil(network); return cached; }
      const res = await network;
      if (res) return res;
      if (req.mode === 'navigate') return cache.match('index.html');
      return Response.error();
    }),
  );
});
