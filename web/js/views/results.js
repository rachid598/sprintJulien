import { html, useState, parseNumber, Notice } from './common.js';
import { ranked, participantLabel } from '../core/results.js';
import { formatTime } from '../core/timing.js';
import { exportCSV, exportPDF, exportPhotoPNG, exportCaptureFiles, exportJSON } from '../services/exporter.js';

function EditDialog({ ctl, result, onClose }) {
  const p = result.participantID ? ctl.race.participants.find((x) => x.id === result.participantID) : null;
  const [name, setName] = useState(p?.name ?? '');
  const [bib, setBib] = useState(p?.bib ?? '');
  const [lane, setLane] = useState(p?.lane ?? '');
  const [time, setTime] = useState(String(result.elapsedSeconds.toFixed(3)).replace('.', ','));
  const [assign, setAssign] = useState(result.participantID ?? '');
  const t = parseNumber(time);
  const save = (e) => {
    e.preventDefault();
    if (!Number.isFinite(t) || t < 0) return;
    if ((assign || null) !== (result.participantID ?? null)) {
      ctl.assignResult(result.id, assign || null);
      const np = ctl.race.participants.find((x) => x.id === assign);
      ctl.editResult(result.id, { name: np?.name ?? '', bib: np?.bib ?? '', lane: np?.lane ?? '', time: t });
    } else {
      ctl.editResult(result.id, { name: name.trim(), bib: bib.trim(), lane: lane.trim(), time: t });
    }
    onClose();
  };
  return html`<div class="modal" role="dialog" aria-modal="true" aria-label="Modifier le résultat" onClick=${(e) => e.target === e.currentTarget && onClose()}>
    <form class="sheet" onSubmit=${save}>
      <h2>Modifier le résultat</h2>
      ${ctl.race.participants.length > 0 && html`<label class="field"><span>Attribuer à</span>
        <select value=${assign} onChange=${(e) => setAssign(e.currentTarget.value)}>
          <option value="">Non attribué</option>
          ${ctl.race.participants.map((x) => html`<option value=${x.id}>${x.name}</option>`)}
        </select></label>`}
      ${(assign || null) === (result.participantID ?? null) && html`
        <label class="field"><span>Nom</span><input value=${name} onInput=${(e) => setName(e.currentTarget.value)} data-testid="edit-name" /></label>
        <div class="row">
          <label class="field grow"><span>Dossard</span><input value=${bib} onInput=${(e) => setBib(e.currentTarget.value)} /></label>
          <label class="field grow"><span>Couloir</span><input value=${lane} onInput=${(e) => setLane(e.currentTarget.value)} /></label>
        </div>`}
      <label class="field"><span>Temps (s)</span><input inputmode="decimal" value=${time} onInput=${(e) => setTime(e.currentTarget.value)} /></label>
      ${!Number.isFinite(t) || t < 0 ? html`<p class="error small">Temps invalide.</p>` : null}
      <div class="row between">
        <button type="button" class="danger" onClick=${() => { ctl.removeResult(result.id); onClose(); }}>Supprimer</button>
        <div class="row">
          <button type="button" class="secondary" onClick=${onClose}>Annuler</button>
          <button type="submit" class="primary" data-testid="edit-save">Enregistrer</button>
        </div>
      </div>
    </form>
  </div>`;
}

export function ResultsList({ ctl }) {
  const [editing, setEditing] = useState(null);
  const race = ctl.race;
  const list = ranked(race.results);
  const editingResult = editing && race.results.find((r) => r.id === editing);
  return html`<section class="group">
    <h2>Résultats · ${list.length}</h2>
    ${list.length === 0 ? html`<p class="muted small">Aucun résultat.</p>` : html`<ol class="results" data-testid="results">
      ${list.map((r, i) => html`<li key=${r.id}>
        <button class="result" onClick=${() => setEditing(r.id)}>
          <span class="rank">${i + 1}</span>
          <span class="grow"><span class="name">${participantLabel(race, r, i + 1)}</span><span class="muted small">${r.source}</span></span>
          <span class="time">${formatTime(r.elapsedSeconds)}</span>
        </button>
        ${Number.isInteger(r.frameIndex) && race.capture?.frames?.length && ctl.phase === 'finished'
          ? html`<button class="icon" aria-label="Aller à l’image" onClick=${() => ctl.selectFrame(r.frameIndex)}>⌖</button>` : null}
      </li>`)}
    </ol>`}
    ${editingResult && html`<${EditDialog} ctl=${ctl} result=${editingResult} onClose=${() => setEditing(null)} />`}
  </section>`;
}

export function ExportMenu({ race }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const run = (fn) => async () => {
    setBusy(true);
    setError(null);
    try { await fn(race); } catch (e) { setError(`Export impossible : ${e.message ?? e}`); }
    setBusy(false);
  };
  return html`<section class="group">
    <h2>Exporter</h2>
    <div class="row wrap">
      <button class="secondary" disabled=${busy} onClick=${run(exportCSV)} data-testid="export-csv">CSV</button>
      <button class="secondary" disabled=${busy} onClick=${run(exportPDF)}>PDF</button>
      ${race.capture?.tiles?.length ? html`<button class="secondary" disabled=${busy} onClick=${run(exportPhotoPNG)}>Photo-finish PNG</button>` : null}
      ${race.capture ? html`<button class="secondary" disabled=${busy} onClick=${run(exportCaptureFiles)}>Fichiers de capture</button>` : null}
      <button class="secondary" disabled=${busy} onClick=${run(exportJSON)}>JSON</button>
    </div>
    <p class="muted small">Le CSV garde six décimales pour l’échange de données ; cela ne certifie pas une précision à la microseconde.</p>
    ${error && html`<${Notice} kind="error">${error}<//>`}
  </section>`;
}
