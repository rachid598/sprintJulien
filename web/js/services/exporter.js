// Exports : CSV, PDF, PNG annoté, fichiers de capture et JSON.
// Dans l'APK (Capacitor), les fichiers passent par Filesystem + Share ;
// dans le navigateur, par la feuille de partage ou un téléchargement.

import { csv, ranked, participantLabel } from '../core/results.js';
import { resultsPDF } from '../core/pdf.js';
import { formatTime } from '../core/timing.js';
import { getFile } from './storage.js';

const native = () => globalThis.Capacitor?.isNativePlatform?.() === true;

export function safeFileName(name) {
  const base = String(name || 'course').normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60);
  return base || 'course';
}

const blobToBase64 = (blob) => new Promise((resolve, reject) => {
  const r = new FileReader();
  r.onload = () => resolve(String(r.result).split(',')[1] ?? '');
  r.onerror = () => reject(r.error);
  r.readAsDataURL(blob);
});

async function shareNative(files) {
  const { registerPlugin } = await import('../vendor/capacitor-core.js');
  const Filesystem = registerPlugin('Filesystem');
  const Share = registerPlugin('Share');
  const uris = [];
  for (const f of files) {
    const res = await Filesystem.writeFile({ path: `export/${f.name}`, data: await blobToBase64(f.blob), directory: 'CACHE', recursive: true });
    uris.push(res.uri);
  }
  await Share.share({ title: files[0]?.name, files: uris, dialogTitle: 'Exporter' });
}

function download(file) {
  const url = URL.createObjectURL(file.blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = file.name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
}

/** @param {{name: string, blob: Blob}[]} files */
export async function shareFiles(files) {
  if (!files.length) return;
  if (native()) return shareNative(files);
  const asFiles = files.map((f) => new File([f.blob], f.name, { type: f.blob.type || 'application/octet-stream' }));
  if (navigator.canShare?.({ files: asFiles })) {
    try {
      await navigator.share({ files: asFiles, title: files[0].name });
      return;
    } catch (err) {
      if (err?.name === 'AbortError') return;
    }
  }
  for (const f of files) download(f);
}

export const exportCSV = (race) => shareFiles([{
  name: `${safeFileName(race.name)}.csv`,
  blob: new Blob(['﻿', csv(race)], { type: 'text/csv;charset=utf-8' }),
}]);

export const exportPDF = (race) => shareFiles([{
  name: `${safeFileName(race.name)}.pdf`,
  blob: new Blob([resultsPDF(race)], { type: 'application/pdf' }),
}]);

export const exportJSON = (race) => shareFiles([{
  name: `${safeFileName(race.name)}.json`,
  blob: new Blob([JSON.stringify(race, null, 2)], { type: 'application/json' }),
}]);

const loadImage = (blob) => new Promise((resolve, reject) => {
  const url = URL.createObjectURL(blob);
  const img = new Image();
  img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
  img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Image illisible')); };
  img.src = url;
});

/**
 * Aperçu PNG annoté du photo-finish, de taille limitée (≤ 8000 px de large).
 * Les tuiles originales restent exportables séparément.
 */
export async function photoFinishPNG(race) {
  const cap = race.capture;
  if (!cap?.tiles?.length) throw new Error('Aucune bande photo-finish.');
  const fullWidth = cap.tiles.reduce((s, t) => s + t.pixelWidth, 0);
  const scale = Math.min(1, 8000 / fullWidth, 1200 / cap.imageHeight);
  const header = 56;
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(fullWidth * scale));
  c.height = Math.round(cap.imageHeight * scale) + header;
  const g = c.getContext('2d');
  g.fillStyle = '#101925';
  g.fillRect(0, 0, c.width, c.height);
  g.imageSmoothingEnabled = false;
  let x = 0;
  for (const tile of cap.tiles) {
    const blob = await getFile(`${race.id}/${tile.relativePath}`);
    if (blob) g.drawImage(await loadImage(blob), Math.round(x * scale), header, Math.round(tile.pixelWidth * scale), c.height - header);
    x += tile.pixelWidth;
  }
  g.fillStyle = '#fff';
  g.font = 'bold 22px system-ui, sans-serif';
  g.fillText(race.name, 12, 34);
  ranked(race.results).forEach((r, i) => {
    if (r.frameIndex === null || r.frameIndex === undefined) return;
    const px = (r.frameIndex + 0.5) * cap.stripWidth * scale;
    g.strokeStyle = '#ff9f0a';
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(px, header);
    g.lineTo(px, c.height);
    g.stroke();
    const label = `${i + 1}. ${participantLabel(race, r, i + 1)} ${formatTime(r.elapsedSeconds)} s`;
    g.font = '15px system-ui, sans-serif';
    const w = g.measureText(label).width + 10;
    const lx = Math.min(c.width - w, Math.max(0, px - w / 2));
    const ly = header + 6 + (i % 4) * 24;
    g.fillStyle = 'rgba(0,0,0,0.7)';
    g.fillRect(lx, ly, w, 21);
    g.fillStyle = '#ff9f0a';
    g.fillText(label, lx + 5, ly + 16);
  });
  return new Promise((resolve) => c.toBlob(resolve, 'image/png'));
}

export async function exportPhotoPNG(race) {
  const blob = await photoFinishPNG(race);
  return shareFiles([{ name: `${safeFileName(race.name)}-photo-finish.png`, blob }]);
}

/** Fichiers de capture originaux : manifeste, tuiles PNG ou vidéo complète. */
export async function exportCaptureFiles(race) {
  const cap = race.capture;
  if (!cap) throw new Error('Aucune capture.');
  const base = safeFileName(race.name);
  const files = [{ name: `${base}-capture.json`, blob: new Blob([JSON.stringify(cap, null, 2)], { type: 'application/json' }) }];
  for (const tile of cap.tiles ?? []) {
    const blob = await getFile(`${race.id}/${tile.relativePath}`);
    if (blob) files.push({ name: `${base}-${tile.relativePath}`, blob });
  }
  if (cap.videoFile) {
    const blob = await getFile(`${race.id}/${cap.videoFile}`);
    if (blob) files.push({ name: `${base}-${cap.videoFile}`, blob });
  }
  return shareFiles(files);
}
