// Générateur PDF minimal (texte, Helvetica, WinAnsi) pour la feuille de
// résultats. Sans dépendance, pour fonctionner hors ligne et dans l'APK.

import { ranked } from './results.js';
import { formatTime } from './timing.js';
import { FINISH_MODES } from './models.js';

const WIN_ANSI = {
  '€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87, 'ˆ': 0x88, '‰': 0x89,
  'Š': 0x8a, '‹': 0x8b, 'Œ': 0x8c, 'Ž': 0x8e, '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95,
  '–': 0x96, '—': 0x97, '˜': 0x98, '™': 0x99, 'š': 0x9a, '›': 0x9b, 'œ': 0x9c, 'ž': 0x9e, 'Ÿ': 0x9f,
};

/** Encode une chaîne en WinAnsi échappée pour un littéral PDF. */
export function pdfString(text) {
  let out = '';
  for (const ch of String(text).normalize('NFC')) {
    const code = ch.codePointAt(0);
    let byte;
    if (code === 0x09 || code === 0x0a || code === 0x0d) byte = 0x20;
    else if (code >= 0x20 && code < 0x7f) byte = code;
    else if (code >= 0xa0 && code <= 0xff) byte = code;
    else byte = WIN_ANSI[ch] ?? 0x3f;
    const c = String.fromCharCode(byte);
    out += c === '(' || c === ')' || c === '\\' ? `\\${c}` : c;
  }
  return `(${out})`;
}

function fit(text, maxChars) {
  const s = String(text ?? '').replace(/\s+/g, ' ').trim();
  return s.length > maxChars ? `${s.slice(0, maxChars - 1)}…` : s;
}

/** Convertit une « chaîne binaire » (octets 0–255) en Uint8Array. */
function toBytes(binary) {
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i) & 0xff;
  return out;
}

export function buildPDF(pages) {
  // pages : tableau de flux de contenu (chaînes binaires).
  const objects = [];
  const add = (body) => { objects.push(body); return objects.length; };
  const catalog = add(null);
  const pagesObj = add(null);
  const font = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  const bold = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  const kids = [];
  for (const content of pages) {
    const stream = add(`<< /Length ${content.length} >>\nstream\n${content}\nendstream`);
    kids.push(add(`<< /Type /Page /Parent ${pagesObj} 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${font} 0 R /F2 ${bold} 0 R >> >> /Contents ${stream} 0 R >>`));
  }
  objects[catalog - 1] = `<< /Type /Catalog /Pages ${pagesObj} 0 R >>`;
  objects[pagesObj - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${kids.length} >>`;
  let out = '%PDF-1.4\n%\xe2\xe3\xcf\xd3\n';
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const o of offsets) out += `${String(o).padStart(10, '0')} 00000 n \n`;
  out += `trailer\n<< /Size ${objects.length + 1} /Root ${catalog} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return toBytes(out);
}

/** Feuille de résultats PDF, une ou plusieurs pages A4. */
export function resultsPDF(race) {
  const people = new Map(race.participants.map((p) => [p.id, p]));
  const rows = ranked(race.results);
  const text = (x, y, size, value, f = 'F1') => `BT /${f} ${size} Tf ${x} ${y} Td ${pdfString(value)} Tj ET\n`;
  const cols = [[40, 'Rang', 5], [80, 'Participant', 30], [270, 'Dossard', 9], [330, 'Couloir', 9], [390, 'Temps (s)', 10], [460, 'Source', 22]];
  const date = new Date(race.date);
  const dateText = Number.isNaN(date.getTime()) ? '' : date.toLocaleString('fr-FR', { dateStyle: 'long', timeStyle: 'short' });
  const pages = [];
  const perPage = 34;
  for (let start = 0; start === 0 || start < rows.length; start += perPage) {
    let s = '';
    let y = 790;
    if (start === 0) {
      s += text(40, y, 20, fit(race.name, 45), 'F2'); y -= 24;
      s += text(40, y, 11, `${dateText} · ${race.distance} m · ${FINISH_MODES[race.mode] ?? race.mode}`); y -= 16;
      s += text(40, y, 9, 'Temps affichés au centième. Mesure non certifiée : réaction, latence et cadence influent sur le résultat.'); y -= 28;
    } else {
      s += text(40, y, 11, `${fit(race.name, 60)} (suite)`, 'F2'); y -= 28;
    }
    for (const [x, label] of cols) s += text(x, y, 10, label, 'F2');
    y -= 6;
    s += `0.6 G 40 ${y} m 555 ${y} l S\n`;
    y -= 16;
    rows.slice(start, start + perPage).forEach((r, i) => {
      const p = r.participantID ? people.get(r.participantID) : null;
      const values = [String(start + i + 1), p?.name || 'Non attribué', p?.bib ?? '', p?.lane ?? '', formatTime(r.elapsedSeconds), r.source ?? ''];
      cols.forEach(([x, , max], c) => { s += text(x, y, 10, fit(values[c], max)); });
      y -= 20;
    });
    if (rows.length === 0) s += text(40, y, 10, 'Aucun résultat.');
    s += text(40, 30, 8, `SprintTimer · page ${pages.length + 1}`);
    pages.push(s);
    if (rows.length === 0) break;
  }
  return buildPDF(pages);
}
