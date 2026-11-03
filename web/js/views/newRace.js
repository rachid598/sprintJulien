import { html, useState, Slider, parseNumber } from './common.js';
import { FINISH_MODES, START_MODES, DISTANCES, defaultSettings, newParticipant, newRace, sanitizeSettings } from '../core/models.js';

const MODE_HELP = {
  photo: 'Bandes verticales horodatées et assemblées pour départager les arrivées.',
  video: 'Images de contrôle horodatées, indicateur de mouvement et analyse image par image.',
  instant: 'Détection de mouvement, résultats immédiats estimés et images de contrôle.',
  stopwatch: 'Départ et arrivées manuels, sans caméra.',
};

const localInput = (d) => {
  const off = d.getTimezoneOffset() * 60000;
  return new Date(d.getTime() - off).toISOString().slice(0, 16);
};

export function NewRace({ onCancel, onCreate }) {
  const [name, setName] = useState('');
  const [date, setDate] = useState(localInput(new Date()));
  const [mode, setMode] = useState('photo');
  const [distance, setDistance] = useState(100);
  const [custom, setCustom] = useState('100');
  const [settings, setSettings] = useState(defaultSettings());
  const [offsetText, setOffsetText] = useState('0');
  const [participants, setParticipants] = useState([]);
  const set = (patch) => setSettings((s) => ({ ...s, ...patch }));
  const setP = (id, patch) => setParticipants((list) => list.map((p) => (p.id === id ? { ...p, ...patch } : p)));

  const submit = (e) => {
    e.preventDefault();
    const title = name.trim();
    const meters = distance === 0 ? parseNumber(custom) : distance;
    const when = new Date(date);
    const s = sanitizeSettings({ ...settings, startOffsetSeconds: parseNumber(offsetText) });
    onCreate(newRace({
      name: title || `Course du ${new Date().toLocaleString('fr-FR', { dateStyle: 'medium', timeStyle: 'short' })}`,
      date: Number.isNaN(when.getTime()) ? new Date().toISOString() : when.toISOString(),
      distance: Number.isFinite(meters) ? Math.max(1, Math.min(100000, meters)) : 100,
      mode,
      settings: s,
      participants: participants.filter((p) => p.name.trim()).map((p) => ({ ...p, name: p.name.trim() })),
    }));
  };

  return html`<form class="screen" onSubmit=${submit}>
    <header class="bar">
      <button type="button" class="link" onClick=${onCancel}>Annuler</button>
      <h1>Nouvelle course</h1>
      <button type="submit" class="link bold" data-testid="prepare">Préparer</button>
    </header>

    <section class="group">
      <h2>Course</h2>
      <label class="field"><span>Nom de la course</span>
        <input value=${name} onInput=${(e) => setName(e.currentTarget.value)} placeholder="ex. 50 m 4e B" data-testid="race-name" /></label>
      <label class="field"><span>Date</span>
        <input type="datetime-local" value=${date} onInput=${(e) => setDate(e.currentTarget.value)} /></label>
      <label class="field"><span>Distance</span>
        <select value=${distance} onChange=${(e) => setDistance(Number(e.currentTarget.value))}>
          ${DISTANCES.map((d) => html`<option value=${d}>${d} m</option>`)}
          <option value="0">Personnalisée</option>
        </select></label>
      ${distance === 0 && html`<label class="field"><span>Distance en mètres</span>
        <input inputmode="decimal" value=${custom} onInput=${(e) => setCustom(e.currentTarget.value)} /></label>`}
      <label class="field"><span>Mode d’arrivée</span>
        <select value=${mode} onChange=${(e) => setMode(e.currentTarget.value)} data-testid="race-mode">
          ${Object.entries(FINISH_MODES).map(([k, v]) => html`<option value=${k}>${v}</option>`)}
        </select></label>
      <p class="muted small">${MODE_HELP[mode]}</p>
    </section>

    <section class="group">
      <h2>Départ</h2>
      <label class="field"><span>Déclenchement</span>
        <select value=${settings.startMode} onChange=${(e) => set({ startMode: e.currentTarget.value })} data-testid="start-mode">
          ${Object.entries(START_MODES).map(([k, v]) => html`<option value=${k}>${v}</option>`)}
        </select></label>
      ${settings.startMode === 'countdown' && html`<label class="field"><span>Compte à rebours : ${settings.countdownSeconds} s</span>
        <input type="range" min="1" max="60" step="1" value=${settings.countdownSeconds} onInput=${(e) => set({ countdownSeconds: Number(e.currentTarget.value) })} /></label>`}
      ${settings.startMode === 'microphone' && html`
        <${Slider} label="Seuil sonore" value=${settings.microphoneThreshold} min="0.02" max="0.95" onInput=${(v) => set({ microphoneThreshold: v })} />
        <p class="muted small">Le premier échantillon dépassant le seuil déclenche le départ. Évitez les conversations à proximité et faites un essai.</p>`}
      <label class="field"><span>Décalage du départ (s)</span>
        <input inputmode="decimal" value=${offsetText} onInput=${(e) => setOffsetText(e.currentTarget.value)} /></label>
      <p class="muted small">Décalage positif : ajoute du temps. Le départ avec bip utilise l’instant programmé ; la latence acoustique doit être calibrée.</p>
    </section>

    ${mode !== 'stopwatch' && html`<section class="group">
      <h2>Caméra · réglages avant la course</h2>
      <${Slider} label="Position de la ligne" value=${settings.linePosition} min="0.05" max="0.95" onInput=${(v) => set({ linePosition: v })} />
      ${mode === 'photo' && html`<label class="field"><span>Largeur de bande : ${settings.stripWidth} px</span>
        <input type="range" min="1" max="16" step="1" value=${settings.stripWidth} onInput=${(e) => set({ stripWidth: Number(e.currentTarget.value) })} /></label>`}
      <label class="field"><span>Cadence demandée</span>
        <select value=${settings.requestedFPS} onChange=${(e) => set({ requestedFPS: Number(e.currentTarget.value) })}>
          ${[30, 60, 120, 240].map((f) => html`<option value=${f}>${f} i/s</option>`)}
        </select></label>
      <label class="field"><span>Capture maximale : ${settings.maxRecordingDuration} s</span>
        <input type="range" min="5" max="120" step="5" value=${settings.maxRecordingDuration} onInput=${(e) => set({ maxRecordingDuration: Number(e.currentTarget.value) })} /></label>
      ${mode !== 'photo' && html`
        <label class="field"><span>Résolution des images de contrôle</span>
          <select value=${settings.reviewHeight} onChange=${(e) => set({ reviewHeight: Number(e.currentTarget.value) })}>
            <option value="480">480 px (léger)</option><option value="640">640 px</option><option value="960">960 px (lourd)</option>
          </select></label>
        <label class="check"><input type="checkbox" checked=${settings.keepVideoFile} onChange=${(e) => set({ keepVideoFile: e.currentTarget.checked })} />
          Enregistrer aussi la vidéo complète pour l’export (charge supplémentaire)</label>`}
      <p class="muted small">La cadence dépend du téléphone et du navigateur, souvent 30 ou 60 i/s. La cadence réellement obtenue est mesurée et affichée. Vidéo et arrivée instantanée sont plafonnés à 60 i/s.</p>
    </section>
    <section class="group">
      <h2>Zone de mouvement</h2>
      <${Slider} label="Largeur de zone" value=${settings.regionWidth} min="0.02" max="0.4" onInput=${(v) => set({ regionWidth: v })} />
      <${Slider} label="Seuil de variation" value=${settings.motionThreshold} min="0.01" max="0.5" onInput=${(v) => set({ motionThreshold: v })} />
      <p class="muted small">Un seuil plus bas augmente la sensibilité.</p>
      <label class="field"><span>Temporisation : ${settings.motionCooldown.toFixed(1).replace('.', ',')} s</span>
        <input type="range" min="0.1" max="5" step="0.1" value=${settings.motionCooldown} onInput=${(e) => set({ motionCooldown: Number(e.currentTarget.value) })} /></label>
    </section>`}

    <section class="group">
      <h2>Participants · ${participants.length}</h2>
      ${participants.map((p, i) => html`<div class="participant" key=${p.id}>
        <input placeholder="Nom du participant" value=${p.name} onInput=${(e) => setP(p.id, { name: e.currentTarget.value })} aria-label=${`Nom du participant ${i + 1}`} />
        <div class="row">
          <input placeholder="Dossard" value=${p.bib} onInput=${(e) => setP(p.id, { bib: e.currentTarget.value })} />
          <input placeholder="Couloir" value=${p.lane} onInput=${(e) => setP(p.id, { lane: e.currentTarget.value })} />
          <button type="button" class="icon danger" aria-label="Retirer" onClick=${() => setParticipants((l) => l.filter((x) => x.id !== p.id))}>✕</button>
        </div>
      </div>`)}
      <button type="button" class="secondary" onClick=${() => setParticipants((l) => [...l, newParticipant({ lane: String(l.length + 1) })])} data-testid="add-participant">＋ Ajouter un participant</button>
      <p class="muted small">Sans liste, les arrivées sont numérotées. Vous pourrez attribuer un nom lors de l’analyse.</p>
    </section>
    <button type="submit" class="primary big">Préparer la course</button>
  </form>`;
}
