// Capture caméra web : aperçu, bandes photo-finish, images de contrôle JPEG
// et détection de mouvement. Chaque image est horodatée par
// requestVideoFrameCallback sur l'horloge performance.now(), la même que le
// départ. Aucun temps n'est calculé à partir d'une cadence théorique.

import { MotionDetector, luminanceFromRGBA } from '../core/motion.js';
import { FrameTimeline } from '../core/frameTimeline.js';
import { newManifest } from '../core/models.js';
import { putFile } from './storage.js';

const TILE_TARGET = 1024;
const SAMPLE_W = 24;
const SAMPLE_H = 64;
const MAX_PENDING_ENCODES = 12;

const canvas = (w, h) => {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(w));
  c.height = Math.max(1, Math.round(h));
  return c;
};

const toBlob = (c, type, quality) => new Promise((resolve, reject) => {
  c.toBlob((b) => (b ? resolve(b) : reject(new Error('Encodage d’image impossible.'))), type, quality);
});

export function cameraSupported() {
  return !!navigator.mediaDevices?.getUserMedia;
}

export class CameraSession {
  /** @param {HTMLVideoElement} video @param {(e: object) => void} onEvent */
  constructor(video, onEvent) {
    this.video = video;
    this.onEvent = onEvent;
    this.stream = null;
    this.settings = null;
    this.timer = null;
    this.recording = null;
    this.loopHandle = null;
    this.closed = false;
    this.previewDetector = new MotionDetector();
    this.sampleCanvas = canvas(SAMPLE_W, SAMPLE_H);
    this.sampleCtx = this.sampleCanvas.getContext('2d', { willReadFrequently: true });
    this.hasRVFC = 'requestVideoFrameCallback' in HTMLVideoElement.prototype;
    this.frameCounter = 0;
  }

  async open(settings, mode) {
    this.settings = settings;
    this.mode = mode;
    const fps = mode === 'photo' ? settings.requestedFPS : Math.min(60, settings.requestedFPS);
    const constraints = {
      audio: false,
      video: {
        facingMode: { ideal: 'environment' },
        width: { ideal: 1280 },
        height: { ideal: 720 },
        frameRate: { ideal: fps, min: Math.min(24, fps) },
        resizeMode: 'none',
      },
    };
    try {
      this.stream = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (err) {
      if (err?.name === 'OverconstrainedError') {
        this.stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: { facingMode: { ideal: 'environment' } } });
      } else throw err;
    }
    if (this.closed) { this.stop(); return null; }
    const track = this.stream.getVideoTracks()[0];
    track.addEventListener('ended', () => this.onEvent({ type: 'interrupted', message: 'La caméra a été interrompue.' }));
    this.video.srcObject = this.stream;
    this.video.muted = true;
    this.video.playsInline = true;
    await this.video.play();
    if (!this.video.videoWidth) await new Promise((r) => this.video.addEventListener('loadedmetadata', r, { once: true }));
    this.scheduleFrame();
    const s = track.getSettings();
    return {
      fps: s.frameRate ?? 0,
      width: this.video.videoWidth,
      height: this.video.videoHeight,
      label: track.label,
    };
  }

  updateSettings(settings) {
    this.settings = settings;
  }

  /** Référence au TimingEngine qui fournit le temps écoulé de chaque image. */
  beginTiming(timer) {
    this.timer = timer;
  }

  scheduleFrame() {
    if (this.closed || !this.stream) return;
    if (this.hasRVFC) {
      this.loopHandle = this.video.requestVideoFrameCallback((now, meta) => {
        this.handleFrame(now, meta);
        this.scheduleFrame();
      });
    } else {
      let lastTime = -1;
      const step = (now) => {
        if (this.closed) return;
        const t = this.video.currentTime;
        if (t !== lastTime) {
          lastTime = t;
          this.handleFrame(now, { presentedFrames: ++this.frameCounter, presentationTime: now });
        }
        this.loopHandle = requestAnimationFrame(step);
      };
      this.loopHandle = requestAnimationFrame(step);
    }
  }

  /** Choisit l'horodatage le plus proche de la capture, sur l'horloge performance. */
  frameTime(now, meta) {
    const current = performance.now();
    const ct = meta.captureTime;
    if (Number.isFinite(ct) && ct > 0 && ct <= current + 5 && current - ct < 1000) return { ms: ct, source: 'capture' };
    const pt = meta.presentationTime;
    if (Number.isFinite(pt) && pt > 0) return { ms: pt, source: 'presentation' };
    return { ms: now, source: 'animation' };
  }

  sampleLuminance() {
    const v = this.video;
    const vw = v.videoWidth;
    const vh = v.videoHeight;
    const rw = Math.max(2, this.settings.regionWidth * vw);
    const rx = Math.min(vw - rw, Math.max(0, this.settings.linePosition * vw - rw / 2));
    this.sampleCtx.drawImage(v, rx, 0, rw, vh, 0, 0, SAMPLE_W, SAMPLE_H);
    return luminanceFromRGBA(this.sampleCtx.getImageData(0, 0, SAMPLE_W, SAMPLE_H).data);
  }

  handleFrame(now, meta) {
    const v = this.video;
    if (!v.videoWidth || !this.settings) return;
    const rec = this.recording;
    const time = this.frameTime(now, meta);
    const host = time.ms / 1000;
    if (!rec) {
      // Indicateur de mouvement de l'aperçu, une image sur trois.
      if ((meta.presentedFrames ?? 0) % 3 === 0) {
        const r = this.previewDetector.process(this.sampleLuminance(), host);
        this.onEvent({ type: 'motion', score: r.score });
      }
      return;
    }
    if (rec.finishing) return;
    if (meta.presentedFrames !== undefined) {
      if (rec.lastPresented !== null && meta.presentedFrames > rec.lastPresented + 1) {
        rec.dropped += meta.presentedFrames - rec.lastPresented - 1;
      }
      rec.lastPresented = meta.presentedFrames;
    }
    const elapsed = this.timer ? this.timer.elapsed(host) : 0;
    const last = rec.frames[rec.frames.length - 1];
    const presentation = (Number.isFinite(meta.presentationTime) ? meta.presentationTime : now) / 1000;
    if (!(elapsed > 0) || (last && (host <= last.hostSeconds || elapsed <= last.elapsedSeconds || presentation <= last.presentationSeconds))) return;
    if (rec.vw !== v.videoWidth || rec.vh !== v.videoHeight) {
      rec.warnings.add('La résolution de la caméra a changé pendant la capture ; capture arrêtée.');
      this.finishRecording(true);
      return;
    }
    if (rec.pending > MAX_PENDING_ENCODES) { rec.dropped += 1; rec.encoderDrops += 1; return; }
    rec.timeSources.add(time.source);

    const position = rec.frames.length;
    const luminance = this.sampleLuminance();
    const motion = rec.detector.process(luminance, host);
    rec.frames.push({
      index: meta.presentedFrames ?? position,
      presentationSeconds: presentation,
      hostSeconds: host,
      elapsedSeconds: elapsed,
      motionScore: motion.score,
    });

    if (rec.mode === 'photo') this.appendStrip(rec, position);
    else this.storeReviewFrame(rec, position);

    if (rec.mode === 'instant' && motion.triggered) {
      this.onEvent({ type: 'crossing', elapsed, frame: position });
    }
    if (position % 6 === 0) {
      this.onEvent({ type: 'progress', frames: rec.frames.length, dropped: rec.dropped, motion: motion.score });
    }
    if (host - rec.startHost >= this.settings.maxRecordingDuration) this.finishRecording(false);
  }

  appendStrip(rec, position) {
    const sw = rec.stripWidth;
    const vw = rec.vw;
    const center = Math.round(this.settings.linePosition * (vw - 1));
    const left = Math.min(vw - sw, Math.max(0, center - Math.floor(sw / 2)));
    if (!rec.tile) {
      rec.tile = { canvas: canvas(rec.tileFrames * sw, rec.vh), startFrame: position, count: 0 };
      rec.tile.ctx = rec.tile.canvas.getContext('2d');
      rec.tile.ctx.imageSmoothingEnabled = false;
    }
    const t = rec.tile;
    t.ctx.drawImage(this.video, left, 0, sw, rec.vh, t.count * sw, 0, sw, rec.vh);
    t.count += 1;
    if (t.count >= rec.tileFrames) this.flushTile(rec);
  }

  flushTile(rec) {
    const t = rec.tile;
    if (!t || t.count === 0) return;
    rec.tile = null;
    const width = t.count * rec.stripWidth;
    let source = t.canvas;
    if (width < t.canvas.width) {
      source = canvas(width, rec.vh);
      source.getContext('2d').drawImage(t.canvas, 0, 0, width, rec.vh, 0, 0, width, rec.vh);
    }
    const n = rec.tiles.length;
    const path = `tile-${String(n).padStart(4, '0')}.png`;
    rec.tiles.push({ relativePath: path, startFrame: t.startFrame, frameCount: t.count, pixelWidth: width, pixelHeight: rec.vh });
    this.track(rec, toBlob(source, 'image/png').then((blob) => putFile(`${rec.raceId}/${path}`, blob)));
  }

  storeReviewFrame(rec, position) {
    const c = rec.reviewCanvas;
    rec.reviewCtx.drawImage(this.video, 0, 0, c.width, c.height);
    const key = `${rec.raceId}/f-${position}.jpg`;
    this.track(rec, toBlob(c, 'image/jpeg', 0.8).then((blob) => putFile(key, blob)));
  }

  track(rec, promise) {
    rec.pending += 1;
    const p = promise
      .catch((err) => { rec.warnings.add(`Écriture d’une image impossible : ${err.message ?? err}`); })
      .finally(() => { rec.pending -= 1; });
    rec.writes.push(p);
  }

  startRecording(raceId, mode) {
    if (this.recording || !this.stream) return;
    const v = this.video;
    const s = this.settings;
    const vw = v.videoWidth;
    const vh = v.videoHeight;
    const stripWidth = Math.min(s.stripWidth, vw);
    const reviewH = Math.min(s.reviewHeight, vh);
    const rec = {
      raceId, mode, vw, vh, stripWidth,
      tileFrames: Math.max(1, Math.floor(TILE_TARGET / stripWidth)),
      startHost: performance.now() / 1000,
      frames: [], tiles: [], tile: null,
      dropped: 0, encoderDrops: 0, lastPresented: null,
      detector: new MotionDetector(s.motionThreshold, s.motionCooldown),
      pending: 0, writes: [], warnings: new Set(), timeSources: new Set(),
      finishing: false, mediaRecorder: null, videoChunks: [], videoFile: null,
    };
    if (mode !== 'photo') {
      rec.reviewCanvas = canvas(Math.round((vw * reviewH) / vh), reviewH);
      rec.reviewCtx = rec.reviewCanvas.getContext('2d');
      if (s.keepVideoFile && globalThis.MediaRecorder) this.startMediaRecorder(rec);
    }
    if (!this.hasRVFC) rec.warnings.add('Navigateur sans requestVideoFrameCallback : horodatage approximatif à la cadence d’affichage.');
    this.recording = rec;
  }

  startMediaRecorder(rec) {
    const types = ['video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm'];
    const mimeType = types.find((t) => MediaRecorder.isTypeSupported?.(t));
    try {
      const mr = new MediaRecorder(this.stream, mimeType ? { mimeType } : undefined);
      mr.ondataavailable = (e) => { if (e.data?.size) rec.videoChunks.push(e.data); };
      mr.start(1000);
      rec.mediaRecorder = mr;
    } catch (err) {
      rec.warnings.add(`Vidéo complète non enregistrée : ${err.message}`);
    }
  }

  stopMediaRecorder(rec) {
    const mr = rec.mediaRecorder;
    if (!mr || mr.state === 'inactive') return Promise.resolve();
    return new Promise((resolve) => {
      mr.onstop = async () => {
        const type = mr.mimeType || rec.videoChunks[0]?.type || 'video/webm';
        const ext = type.includes('mp4') ? 'mp4' : 'webm';
        const blob = new Blob(rec.videoChunks, { type });
        rec.videoFile = `video.${ext}`;
        try { await putFile(`${rec.raceId}/${rec.videoFile}`, blob); } catch (err) { rec.warnings.add(`Vidéo non sauvegardée : ${err.message}`); rec.videoFile = null; }
        resolve();
      };
      mr.stop();
    });
  }

  stopRecording() {
    return this.finishRecording(false);
  }

  /** Finalise la capture et émet { type: 'finished', manifest }. */
  async finishRecording(interrupted) {
    const rec = this.recording;
    if (!rec || rec.finishing) return rec?.done;
    rec.finishing = true;
    rec.done = (async () => {
      if (rec.mode === 'photo') this.flushTile(rec);
      await this.stopMediaRecorder(rec);
      await Promise.all(rec.writes);
      const timeline = new FrameTimeline(rec.frames);
      if (rec.timeSources.has('presentation') || rec.timeSources.has('animation')) {
        rec.warnings.add('Horodatage de présentation (pas de capture) : le retard de traitement de la caméra n’est pas compensé ; à calibrer avec le décalage de départ.');
      }
      if (rec.encoderDrops) rec.warnings.add(`${rec.encoderDrops} image(s) ignorée(s) : encodage trop lent.`);
      if (!timeline.isValid) rec.warnings.add('Chronologie des images invalide.');
      if (rec.frames.length === 0) rec.warnings.add('Aucune image capturée.');
      const manifest = newManifest({
        raceID: rec.raceId,
        mode: rec.mode,
        imageWidth: rec.mode === 'photo' ? rec.vw : rec.reviewCanvas.width,
        imageHeight: rec.mode === 'photo' ? rec.vh : rec.reviewCanvas.height,
        stripWidth: rec.stripWidth,
        frames: rec.frames,
        tiles: rec.tiles,
        videoFile: rec.videoFile,
        droppedFrames: rec.dropped,
        requestedFPS: this.settings.requestedFPS,
        actualFPS: timeline.effectiveFPS,
        startHostSeconds: this.timer?.startHostSeconds ?? 0,
        startOffsetSeconds: this.settings.startOffsetSeconds,
        interrupted,
        warnings: [...rec.warnings],
        timestampSource: [...rec.timeSources].join(', ') || 'aucune',
        sourceWidth: rec.vw,
        sourceHeight: rec.vh,
      });
      this.recording = null;
      this.onEvent({ type: 'finished', manifest });
      return manifest;
    })();
    return rec.done;
  }

  stop() {
    this.closed = true;
    if (this.loopHandle !== null) {
      if (this.hasRVFC) this.video.cancelVideoFrameCallback?.(this.loopHandle);
      else cancelAnimationFrame(this.loopHandle);
    }
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.video.srcObject = null;
  }
}
