import { html, useEffect, useRef, useObservable, Slider, Notice } from './common.js';
import { FINISH_MODES, START_MODES } from '../core/models.js';
import { formatTime } from '../core/timing.js';
import { PhotoStrip, VideoReview } from './analysis.js';
import { ResultsList, ExportMenu } from './results.js';

const START_LABEL = {
  manual: 'Démarrer',
  sound: 'Démarrer avec le bip',
  countdown: 'Lancer le compte à rebours',
  microphone: 'Armer le micro',
};

function Clock({ ctl }) {
  const ref = useRef(null);
  useEffect(() => {
    let id;
    const loop = () => {
      if (ref.current) ref.current.textContent = formatTime(ctl.elapsed);
      id = requestAnimationFrame(loop);
    };
    loop();
    return () => cancelAnimationFrame(id);
  }, [ctl]);
  return html`<div class="clock" ref=${ref} data-testid="clock" aria-live="off">${formatTime(ctl.elapsed)}</div>`;
}

function Meter({ value, label }) {
  return html`<div class="meter" role="meter" aria-label=${label} aria-valuenow=${Math.round(value * 100)} aria-valuemin="0" aria-valuemax="100">
    <div style=${{ width: `${Math.min(100, value * 100)}%` }}></div>
  </div>`;
}

function Preview({ ctl }) {
  const video = useRef(null);
  const s = ctl.race.settings;
  const info = ctl.cameraInfo;
  useEffect(() => {
    ctl.attachVideo(video.current);
    if (ctl.phase === 'preparing' || (ctl.phase === 'ready' && !ctl.cameraReady)) ctl.prepare();
  }, [ctl, ctl.race.id]);
  const ratio = info ? info.width / info.height : 9 / 16;
  return html`<div class="preview" style=${{ aspectRatio: `${ratio}`, width: `min(100%, calc(58dvh * ${ratio}))` }}>
    <video ref=${video} playsinline muted autoplay data-testid="preview"></video>
    <div class="zone" style=${{ left: `${(s.linePosition - s.regionWidth / 2) * 100}%`, width: `${s.regionWidth * 100}%` }}></div>
    <div class="line" style=${{ left: `${s.linePosition * 100}%` }}></div>
    ${!ctl.cameraReady && html`<div class="overlay">Ouverture de la caméra…</div>`}
    ${ctl.phase === 'countdown' && html`<div class="overlay big">${ctl.countdown}</div>`}
    ${ctl.phase === 'recording' && html`<div class="rec">● REC</div>`}
  </div>`;
}

function LiveControls({ ctl }) {
  const s = ctl.race.settings;
  const camera = ctl.usesCamera;
  switch (ctl.phase) {
    case 'preparing':
      return html`<p class="muted">Préparation…</p>`;
    case 'ready':
      return html`
        ${camera && ctl.cameraReady && html`<div class="group">
          <${Slider} label="Position de la ligne" value=${s.linePosition} min="0.05" max="0.95" onInput=${(v) => ctl.updateSettings({ linePosition: v })} />
          <${Slider} label="Largeur de la zone de mouvement" value=${s.regionWidth} min="0.02" max="0.4" onInput=${(v) => ctl.updateSettings({ regionWidth: v })} />
          <p class="muted small">Stabilisez le téléphone, alignez la ligne orange avec la ligne d’arrivée réelle et cadrez tous les couloirs.</p>
        </div>`}
        ${camera && !ctl.cameraReady && html`<button class="secondary" onClick=${() => ctl.prepare()}>Réessayer la caméra</button>`}
        <button class="primary big" disabled=${camera && !ctl.cameraReady} onClick=${() => ctl.start()} data-testid="start">${START_LABEL[s.startMode]}</button>`;
    case 'armed':
      return html`<p>Micro armé : produisez le signal de départ.</p>
        <${Meter} value=${ctl.micLevel} label="Niveau sonore" />
        <p class="muted small">Seuil : ${Math.round(s.microphoneThreshold * 100)} %</p>
        <button class="secondary big" onClick=${() => ctl.cancelStart()}>Annuler</button>`;
    case 'countdown':
      return html`<p class="countdown">${ctl.countdown}</p><button class="secondary big" onClick=${() => ctl.cancelStart()}>Annuler</button>`;
    case 'running':
      return camera
        ? html`<button class="primary big" onClick=${() => ctl.record()} data-testid="record">Capturer les arrivées</button>
            <button class="danger" onClick=${() => ctl.stop()} data-testid="stop">Arrêter la course</button>`
        : html`<button class="primary huge" onClick=${() => ctl.markManual()} data-testid="mark">Marquer l’arrivée</button>
            <button class="danger" onClick=${() => ctl.stop()} data-testid="stop">Arrêter la course</button>`;
    case 'recording':
      return html`<p class="small">${ctl.frames} images capturées${ctl.dropped ? ` · ${ctl.dropped} perdue(s)` : ''}</p>
        <button class="danger big" onClick=${() => ctl.stop()} data-testid="finish-capture">Terminer la capture</button>`;
    case 'processing':
      return html`<p class="muted">Finalisation de la capture…</p>`;
    default:
      return null;
  }
}

export function RaceScreen({ ctl, onClose }) {
  useObservable(ctl);
  const race = ctl.race;
  useEffect(() => {
    const vis = () => (document.hidden ? ctl.background() : ctl.resume());
    document.addEventListener('visibilitychange', vis);
    return () => { document.removeEventListener('visibilitychange', vis); ctl.close(); };
  }, [ctl]);
  // Sans caméra, aucune prévisualisation ne déclenche la préparation.
  useEffect(() => { if (!ctl.usesCamera && ctl.phase === 'preparing') ctl.prepare(); }, [ctl, ctl.phase]);

  const leave = () => {
    if (!ctl.canLeave && !confirm('Arrêter la course en cours et revenir à l’accueil ?')) return;
    onClose();
  };
  const finished = ctl.phase === 'finished';
  const cap = race.capture;
  const showPreview = ctl.usesCamera && !finished;

  return html`<main class="screen race">
    <header class="bar">
      <button class="link" onClick=${leave} data-testid="back">‹ Accueil</button>
      <h1 class="ellipsis">${race.name}</h1>
      <span class="muted small">${FINISH_MODES[race.mode]}</span>
    </header>
    ${ctl.errorMessage && html`<${Notice} kind="error">${ctl.errorMessage}<//>`}
    ${ctl.saveProblem && html`<${Notice} kind="error">${ctl.saveProblem}<//>`}
    ${showPreview && html`<${Preview} ctl=${ctl} />`}
    ${showPreview && ctl.cameraReady && html`<div class="row between small muted">
      <span>${ctl.cameraInfo.width}×${ctl.cameraInfo.height} · ${Math.round(ctl.cameraInfo.fps || 0)} i/s annoncés</span>
      <span class="row">Mouvement <${Meter} value=${ctl.motion * 3} label="Mouvement dans la zone" /></span>
    </div>`}
    <${Clock} ctl=${ctl} />
    <p class="muted small center">${race.distance} m · départ ${START_MODES[race.settings.startMode].toLowerCase()}${race.settings.startOffsetSeconds ? ` · décalage ${race.settings.startOffsetSeconds} s` : ''}</p>
    <div class="controls"><${LiveControls} ctl=${ctl} /></div>
    ${finished && cap?.mode === 'photo' && html`<${PhotoStrip} ctl=${ctl} />`}
    ${finished && (cap?.mode === 'video' || cap?.mode === 'instant') && html`<${VideoReview} ctl=${ctl} />`}
    ${finished && ctl.usesCamera && !cap && html`<${Notice}>Aucune capture d’arrivée pour cette course.<//>`}
    <${ResultsList} ctl=${ctl} />
    ${finished && html`<${ExportMenu} race=${race} />
      <div class="row wrap">
        <button class="primary" onClick=${() => ctl.retry()} data-testid="retry">Nouvelle tentative</button>
        <button class="secondary" onClick=${onClose}>Fermer</button>
      </div>`}
  </main>`;
}
