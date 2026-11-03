// Analyse après capture : bande photo-finish et revue image par image.
import { html, useEffect, useMemo, useRef, useState } from './common.js';
import { FrameTimeline } from '../core/frameTimeline.js';
import { formatTime } from '../core/timing.js';
import { ranked } from '../core/results.js';
import { getFile } from '../services/storage.js';

function useTileURLs(race) {
  const [urls, setUrls] = useState(null);
  useEffect(() => {
    let alive = true;
    const made = [];
    (async () => {
      const list = [];
      for (const t of race.capture.tiles) {
        const blob = await getFile(`${race.id}/${t.relativePath}`);
        const u = blob ? URL.createObjectURL(blob) : null;
        if (u) made.push(u);
        list.push(u);
      }
      if (alive) setUrls(list);
    })();
    return () => { alive = false; made.forEach((u) => URL.revokeObjectURL(u)); };
  }, [race.id, race.capture]);
  return urls;
}

function FrameNav({ ctl, count }) {
  const go = (d) => ctl.selectFrame(ctl.selectedFrame + d);
  return html`<div class="row center nav">
    <button class="icon" aria-label="Reculer de 10 images" onClick=${() => go(-10)}>⏪</button>
    <button class="icon" aria-label="Image précédente" onClick=${() => go(-1)} data-testid="prev-frame">◀</button>
    <span class="small muted">${ctl.selectedFrame + 1} / ${count}</span>
    <button class="icon" aria-label="Image suivante" onClick=${() => go(1)} data-testid="next-frame">▶</button>
    <button class="icon" aria-label="Avancer de 10 images" onClick=${() => go(10)}>⏩</button>
  </div>`;
}

function CaptureInfo({ cap }) {
  const timeline = useMemo(() => new FrameTimeline(cap.frames), [cap]);
  const gap = timeline.maxFrameGap;
  return html`<p class="muted small">
    ${cap.frames.length} images · cadence mesurée ${timeline.effectiveFPS.toFixed(1).replace('.', ',')} i/s
    ${gap ? ` · écart max ${(gap * 1000).toFixed(1).replace('.', ',')} ms` : ''}
    ${cap.droppedFrames ? ` · ${cap.droppedFrames} image(s) perdue(s)` : ''}
    ${cap.timestampSource ? ` · horodatage : ${cap.timestampSource}` : ''}
  </p>
  ${cap.warnings?.length ? html`<ul class="warnings small">${cap.warnings.map((w) => html`<li>${w}</li>`)}</ul>` : null}`;
}

function MarkBar({ ctl, ready = true }) {
  const race = ctl.race;
  const stamp = ctl.currentStamp;
  return html`<div class="markbar">
    <div class="time-big" data-testid="frame-time">${stamp ? `${formatTime(stamp.elapsedSeconds)} s` : '—'}</div>
    <select value=${ctl.selectedParticipant ?? ''} onChange=${(e) => { ctl.selectedParticipant = e.currentTarget.value || null; ctl.emit(); }} aria-label="Participant">
      <option value="">Arrivée sans nom</option>
      ${race.participants.map((p) => html`<option value=${p.id}>${p.name}${race.results.some((r) => r.participantID === p.id) ? ' ✓' : ''}</option>`)}
    </select>
    <button class="primary" disabled=${!stamp || !ready} onClick=${() => ctl.markFrame()} data-testid="mark-frame">Marquer ce temps</button>
  </div>`;
}

export function PhotoStrip({ ctl }) {
  const race = ctl.race;
  const cap = race.capture;
  const urls = useTileURLs(race);
  const scroller = useRef(null);
  const [zoom, setZoom] = useState(2);
  const [height, setHeight] = useState(360);
  const timeline = useMemo(() => new FrameTimeline(cap.frames), [cap]);
  useEffect(() => {
    const fit = () => setHeight(Math.round(Math.min(520, Math.max(220, window.innerHeight * 0.48))));
    fit();
    addEventListener('resize', fit);
    return () => removeEventListener('resize', fit);
  }, []);
  const scaleY = height / cap.imageHeight;
  const sx = scaleY * zoom; // pixels affichés par pixel source horizontal
  const frameW = cap.stripWidth * sx;
  // Zoom initial : une capture courte remplit la largeur disponible.
  useEffect(() => {
    const w = scroller.current?.clientWidth;
    const natural = cap.frames.length * cap.stripWidth * (height / cap.imageHeight);
    if (w && natural > 0) setZoom(Math.max(2, Math.min(32, Math.floor(w / natural))));
  }, [cap]);

  // Garde le curseur visible quand on navigue avec les flèches.
  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const x = (ctl.selectedFrame + 0.5) * frameW;
    if (x < el.scrollLeft + 20 || x > el.scrollLeft + el.clientWidth - 20) el.scrollLeft = x - el.clientWidth / 2;
  }, [ctl.selectedFrame, frameW]);

  const pick = (e) => {
    const el = scroller.current;
    const rect = el.getBoundingClientRect();
    const px = (e.clientX - rect.left + el.scrollLeft) / sx;
    const i = timeline.indexAtPixel(px, cap.stripWidth);
    if (i !== null) ctl.selectFrame(i);
  };

  if (!cap.frames.length) return html`<p class="muted">Aucune image capturée.</p>`;
  const marks = ranked(race.results).map((r, i) => ({ r, rank: i + 1 })).filter(({ r }) => Number.isInteger(r.frameIndex));
  return html`<section class="analysis">
    <div class="strip" ref=${scroller} style=${{ height: `${height}px` }} onClick=${pick} data-testid="photo-strip">
      <div class="strip-inner" style=${{ width: `${cap.frames.length * frameW}px`, height: `${height}px` }}>
        ${urls === null ? html`<p class="muted pad">Chargement des bandes…</p>`
          : cap.tiles.map((t, i) => html`<img key=${t.relativePath} src=${urls[i]} alt="" draggable="false"
              style=${{ left: `${t.startFrame * frameW}px`, width: `${t.pixelWidth * sx}px`, height: `${height}px` }} />`)}
        ${marks.map(({ r, rank }) => html`<div class="mark" style=${{ left: `${(r.frameIndex + 0.5) * frameW}px` }}><span>${rank}</span></div>`)}
        <div class="cursor" style=${{ left: `${(ctl.selectedFrame + 0.5) * frameW}px` }}></div>
      </div>
    </div>
    <label class="field compact"><span class="row between"><span>Zoom horizontal</span><span class="muted">×${zoom}</span></span>
      <input type="range" min="1" max="32" step="1" value=${zoom} onInput=${(e) => setZoom(Number(e.currentTarget.value))} /></label>
    <${FrameNav} ctl=${ctl} count=${cap.frames.length} />
    <${MarkBar} ctl=${ctl} />
    <${CaptureInfo} cap=${cap} />
  </section>`;
}

function MotionGraph({ ctl }) {
  const ref = useRef(null);
  const frames = ctl.race.capture.frames;
  useEffect(() => {
    const c = ref.current;
    if (!c) return;
    const w = (c.width = c.clientWidth * devicePixelRatio);
    const h = (c.height = 48 * devicePixelRatio);
    const g = c.getContext('2d');
    g.clearRect(0, 0, w, h);
    const max = Math.max(0.05, ...frames.map((f) => f.motionScore));
    g.fillStyle = '#ff9f0a';
    frames.forEach((f, i) => {
      const x = (i / frames.length) * w;
      const bh = (f.motionScore / max) * h;
      g.fillRect(x, h - bh, Math.max(1, w / frames.length), bh);
    });
    g.fillStyle = '#0a84ff';
    g.fillRect((ctl.selectedFrame / frames.length) * w - devicePixelRatio, 0, 2 * devicePixelRatio, h);
  });
  const pick = (e) => {
    const rect = ref.current.getBoundingClientRect();
    ctl.selectFrame(((e.clientX - rect.left) / rect.width) * frames.length);
  };
  return html`<canvas class="graph" ref=${ref} onClick=${pick} aria-label="Score de mouvement par image"></canvas>`;
}

export function VideoReview({ ctl }) {
  const race = ctl.race;
  const cap = race.capture;
  const [url, setUrl] = useState(null);
  const [loaded, setLoaded] = useState(-1);
  const frame = ctl.selectedFrame;
  useEffect(() => {
    let alive = true;
    let made = null;
    getFile(`${race.id}/f-${frame}.jpg`).then((blob) => {
      if (!alive) return;
      made = blob ? URL.createObjectURL(blob) : null;
      setUrl(made);
      if (!blob) setLoaded(-1);
    });
    return () => { alive = false; if (made) setTimeout(() => URL.revokeObjectURL(made), 1000); };
  }, [race.id, frame]);

  useEffect(() => {
    const key = (e) => {
      if (e.target.closest?.('input, select, textarea')) return;
      if (e.key === 'ArrowLeft') ctl.selectFrame(ctl.selectedFrame - 1);
      if (e.key === 'ArrowRight') ctl.selectFrame(ctl.selectedFrame + 1);
    };
    addEventListener('keydown', key);
    return () => removeEventListener('keydown', key);
  }, [ctl]);

  if (!cap.frames.length) return html`<p class="muted">Aucune image capturée.</p>`;
  const stamp = ctl.currentStamp;
  return html`<section class="analysis">
    <div class="frame-view" style=${{ aspectRatio: `${cap.imageWidth / cap.imageHeight}`, width: `min(100%, calc(60dvh * ${cap.imageWidth / cap.imageHeight}))` }}>
      ${url && html`<img src=${url} alt=${`Image ${frame + 1}`} onLoad=${() => setLoaded(frame)} data-testid="review-frame" />`}
      <div class="line" style=${{ left: `${race.settings.linePosition * 100}%` }}></div>
    </div>
    <input type="range" class="scrub" min="0" max=${cap.frames.length - 1} step="1" value=${frame}
      onInput=${(e) => ctl.selectFrame(Number(e.currentTarget.value))} aria-label="Image" />
    <${FrameNav} ctl=${ctl} count=${cap.frames.length} />
    <${MotionGraph} ctl=${ctl} />
    <p class="muted small">Mouvement dans la zone : ${stamp ? Math.round(stamp.motionScore * 100) : 0} %</p>
    <${MarkBar} ctl=${ctl} ready=${loaded === frame} />
    <${CaptureInfo} cap=${cap} />
  </section>`;
}
