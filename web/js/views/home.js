import { html, useEffect, useState, formatDate, Notice } from './common.js';
import { listRaces, deleteRace, storageEstimate } from '../services/storage.js';
import { FINISH_MODES } from '../core/models.js';
import { formatTime } from '../core/timing.js';
import { ranked } from '../core/results.js';

export function Home({ onNew, onOpen, install }) {
  const [races, setRaces] = useState(null);
  const [usage, setUsage] = useState(null);
  const [error, setError] = useState(null);

  const reload = () => listRaces().then(setRaces).catch((e) => setError(`Historique illisible : ${e.message}`));
  useEffect(() => {
    reload();
    storageEstimate().then((e) => e && setUsage(e));
  }, []);

  const remove = async (race) => {
    if (!confirm(`Supprimer « ${race.name} » et ses captures ?`)) return;
    await deleteRace(race.id);
    reload();
  };

  return html`<main class="screen">
    <header class="hero">
      <img src="icons/icon-192.png" alt="" width="56" height="56" />
      <div>
        <h1>SprintTimer</h1>
        <p class="muted">Chronométrage photo-finish, vidéo et manuel</p>
      </div>
    </header>
    <button class="primary big" onClick=${onNew} data-testid="new-race">＋ Nouvelle course</button>
    ${install.canInstall && html`<button class="secondary" onClick=${install.prompt}>Installer l’application</button>`}
    ${install.iosHint && html`<${Notice}>Pour installer sur iPhone : bouton Partager, puis « Sur l’écran d’accueil ».<//>`}
    ${error && html`<${Notice} kind="error">${error}<//>`}
    <h2>Historique</h2>
    ${races === null ? html`<p class="muted">Chargement…</p>`
      : races.length === 0 ? html`<p class="muted">Aucune course enregistrée.</p>`
      : html`<ul class="list">${races.map((r) => {
          const best = ranked(r.results)[0];
          return html`<li key=${r.id} class="card row between">
            <button class="link grow" onClick=${() => onOpen(r)}>
              <strong>${r.name}</strong>
              <span class="muted small">${formatDate(r.date)} · ${r.distance} m · ${FINISH_MODES[r.mode]}</span>
              <span class="small">${r.results.length} résultat(s)${best ? ` · meilleur ${formatTime(best.elapsedSeconds)} s` : ''}${r.capture?.interrupted ? ' · capture interrompue' : ''}</span>
            </button>
            <button class="icon danger" aria-label=${`Supprimer ${r.name}`} onClick=${() => remove(r)}>🗑</button>
          </li>`;
        })}</ul>`}
    ${usage?.quota ? html`<p class="muted small">Stockage local utilisé : ${(usage.usage / 1e6).toFixed(0)} Mo sur ${(usage.quota / 1e6).toFixed(0)} Mo disponibles.</p>` : null}
    <p class="muted small">Les courses et captures restent sur cet appareil. Cette application n’est pas un système de chronométrage certifié.</p>
  </main>`;
}
