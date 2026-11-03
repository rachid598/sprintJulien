export { html, render, useState, useEffect, useRef, useMemo, useCallback, useReducer, useLayoutEffect } from '../vendor/preact-htm.js';
import { html, useEffect, useReducer } from '../vendor/preact-htm.js';

/** Re-rendu à chaque émission d'un objet observable ({ subscribe }). */
export function useObservable(obj) {
  const [, force] = useReducer((x) => x + 1, 0);
  useEffect(() => obj?.subscribe(() => force()), [obj]);
}

export function formatDate(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('fr-FR', { dateStyle: 'medium', timeStyle: 'short' });
}

/** Convertit une saisie française (« 12,34 ») en nombre. */
export function parseNumber(text) {
  const n = Number(String(text).trim().replace(/\s/g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : NaN;
}

export const pct = (v) => `${Math.round(v * 100)} %`;

export function Slider({ label, value, min, max, step = 0.01, format = pct, onInput }) {
  return html`<label class="field">
    <span class="row between"><span>${label}</span><span class="muted">${format(value)}</span></span>
    <input type="range" min=${min} max=${max} step=${step} value=${value} aria-label=${label}
      onInput=${(e) => onInput(Number(e.currentTarget.value))} />
  </label>`;
}

export function Notice({ kind = 'info', children }) {
  return html`<div class=${`notice ${kind}`} role=${kind === 'error' ? 'alert' : 'status'}>${children}</div>`;
}
