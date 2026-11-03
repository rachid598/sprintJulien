// Stockage local IndexedDB : documents de course et fichiers de capture
// (tuiles PNG, images JPEG de contrôle, vidéo). Rien ne quitte l'appareil.

const DB_NAME = 'sprinttimer';
const DB_VERSION = 1;
let dbPromise = null;

function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('races')) db.createObjectStore('races', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('files')) db.createObjectStore('files');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function tx(store, mode, fn) {
  return open().then((db) => new Promise((resolve, reject) => {
    const t = db.transaction(store, mode);
    const s = t.objectStore(store);
    let result;
    Promise.resolve(fn(s)).then((r) => { result = r; });
    t.oncomplete = () => resolve(result);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error ?? new Error('Transaction annulée'));
  }));
}

const reqValue = (req) => new Promise((resolve, reject) => {
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});

export async function requestPersistence() {
  try { if (navigator.storage?.persist) await navigator.storage.persist(); } catch { /* facultatif */ }
}

export async function storageEstimate() {
  try { return await navigator.storage?.estimate?.(); } catch { return null; }
}

export function saveRace(race) {
  // Clone JSON : garantit un document sérialisable identique à l'export.
  const doc = JSON.parse(JSON.stringify(race));
  return tx('races', 'readwrite', (s) => { s.put(doc); });
}

export async function listRaces() {
  const all = await tx('races', 'readonly', (s) => reqValue(s.getAll()));
  return (all ?? []).sort((a, b) => String(b.date).localeCompare(String(a.date)));
}

export function getRace(id) {
  return tx('races', 'readonly', (s) => reqValue(s.get(id)));
}

export function putFile(key, blob) {
  return tx('files', 'readwrite', (s) => { s.put(blob, key); });
}

export function getFile(key) {
  return tx('files', 'readonly', (s) => reqValue(s.get(key)));
}

export async function deleteRace(id) {
  await tx('races', 'readwrite', (s) => { s.delete(id); });
  const range = IDBKeyRange.bound(`${id}/`, `${id}/￿`);
  await tx('files', 'readwrite', (s) => { s.delete(range); });
}
