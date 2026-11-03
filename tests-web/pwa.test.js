// Vérifie que le service worker met en cache tous les fichiers de l'application
// et que le manifeste est installable.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('../web/', import.meta.url).pathname;
const walk = (dir) => readdirSync(dir).flatMap((n) => {
  const p = join(dir, n);
  return statSync(p).isDirectory() ? walk(p) : [p];
});

test('le service worker met en cache chaque fichier publié', () => {
  const sw = readFileSync(join(root, 'sw.js'), 'utf8');
  const listed = new Set([...sw.matchAll(/^\s+'([^']+)',$/gm)].map((m) => m[1]));
  const files = walk(root).map((p) => relative(root, p))
    .filter((p) => p !== 'sw.js' && !p.endsWith('.txt'));
  for (const f of files) assert.ok(listed.has(f), `absent du cache : ${f}`);
  for (const f of listed) if (f !== './') assert.ok(existsSync(join(root, f)), `fichier manquant : ${f}`);
});

test('manifeste installable', () => {
  const m = JSON.parse(readFileSync(join(root, 'manifest.webmanifest'), 'utf8'));
  assert.equal(m.display, 'standalone');
  assert.ok(m.icons.some((i) => i.sizes === '512x512' && i.purpose === 'maskable'));
  assert.ok(m.icons.some((i) => i.sizes === '192x192'));
  for (const i of m.icons) assert.ok(existsSync(join(root, i.src)));
});
