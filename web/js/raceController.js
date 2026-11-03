// Équivalent web de RaceManager.swift : cycle de vie d'une course,
// départs, capture, marquage et sauvegarde.

import { TimingEngine, hostNow } from './core/timing.js';
import { newRace, newResult, newParticipant } from './core/models.js';
import { saveRace } from './services/storage.js';
import { CameraSession, cameraSupported } from './services/camera.js';
import { playStartBeep, armMicrophone, stopMicrophone, tick, unlockAudio } from './services/signals.js';

// Phases : preparing, ready, armed, countdown, running, recording, processing, finished

export class RaceController {
  constructor(race, { reopening = false } = {}) {
    this.race = race;
    this.phase = reopening ? 'finished' : 'preparing';
    this.errorMessage = null;
    this.cameraReady = false;
    this.cameraInfo = null;
    this.frames = 0;
    this.dropped = 0;
    this.motion = 0;
    this.micLevel = 0;
    this.countdown = 0;
    this.selectedFrame = 0;
    this.selectedParticipant = this.firstUnassigned();
    this.saveProblem = null;
    this.timer = new TimingEngine();
    this.camera = null;
    this.video = null;
    this.closed = false;
    this.foreground = true;
    this.listeners = new Set();
    this.wakeLock = null;
    this.countdownHandle = null;
  }

  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  emit() { for (const fn of this.listeners) fn(); }

  get elapsed() { return this.phase === 'finished' ? this.race.elapsedSeconds : this.timer.elapsed(hostNow()); }
  get usesCamera() { return this.race.mode !== 'stopwatch'; }
  get canLeave() { return ['ready', 'finished', 'preparing'].includes(this.phase); }
  get currentStamp() { return this.race.capture?.frames?.[this.selectedFrame] ?? null; }

  firstUnassigned() {
    return this.race.participants.find((p) => !this.race.results.some((r) => r.participantID === p.id))?.id ?? null;
  }

  attachVideo(video) { this.video = video; }

  async prepare() {
    if (this.closed || !this.foreground) return;
    if (!(this.phase === 'preparing' || (this.phase === 'ready' && !this.cameraReady))) return;
    await this.persist();
    if (!this.usesCamera) { this.phase = 'ready'; this.emit(); return; }
    if (!cameraSupported()) {
      this.errorMessage = 'Caméra indisponible : ouvrez l’application en HTTPS dans un navigateur récent, ou créez une course en mode chronomètre.';
      this.phase = 'ready';
      this.emit();
      return;
    }
    if (!this.video) return;
    this.camera?.stop();
    const camera = new CameraSession(this.video, (e) => this.handle(e));
    this.camera = camera;
    try {
      const info = await camera.open(this.race.settings, this.race.mode);
      if (!info || this.closed || this.camera !== camera) return;
      this.cameraInfo = info;
      this.cameraReady = true;
      if (this.phase === 'preparing') this.phase = 'ready';
      this.errorMessage = null;
    } catch (err) {
      this.errorMessage = err?.name === 'NotAllowedError'
        ? 'Autorisez la caméra pour cette application (réglages du navigateur ou du téléphone). Vous pouvez aussi créer une course en mode chronomètre.'
        : `Caméra indisponible : ${err?.message ?? err}`;
      this.phase = 'ready';
    }
    this.emit();
  }

  async start() {
    if (this.phase !== 'ready' || (this.usesCamera && !this.cameraReady)) return;
    this.errorMessage = null;
    const s = this.race.settings;
    try {
      switch (s.startMode) {
        case 'manual':
          this.begin(hostNow());
          unlockAudio().catch(() => {});
          break;
        case 'sound':
          this.begin(await playStartBeep());
          break;
        case 'countdown': {
          await unlockAudio();
          this.phase = 'countdown';
          const deadline = hostNow() + Math.max(1, Math.min(60, s.countdownSeconds));
          let shown = -1;
          const step = async () => {
            if (this.phase !== 'countdown') return;
            const left = deadline - hostNow();
            if (left <= 0.1) {
              this.countdownHandle = null;
              try { this.begin(await playStartBeep(Math.max(0.02, left))); } catch (err) { this.fail(err); }
              return;
            }
            const n = Math.ceil(left);
            if (n !== shown) { shown = n; this.countdown = n; tick(); this.emit(); }
            this.countdownHandle = setTimeout(step, 30);
          };
          step();
          break;
        }
        case 'microphone':
          this.phase = 'armed';
          this.emit();
          await armMicrophone(s.microphoneThreshold,
            (peak) => { this.micLevel = peak; this.emit(); },
            (host) => {
              if (this.phase !== 'armed') return;
              stopMicrophone();
              this.begin(host);
            });
          if (this.phase !== 'armed') stopMicrophone();
          break;
        default:
          this.begin(hostNow());
      }
    } catch (err) {
      this.fail(err);
    }
    this.emit();
  }

  fail(err) {
    this.errorMessage = err?.name === 'NotAllowedError'
      ? 'Autorisez le microphone pour cette application.'
      : (err?.message ?? String(err));
    stopMicrophone();
    if (['armed', 'countdown'].includes(this.phase)) this.phase = 'ready';
    this.emit();
  }

  begin(host) {
    this.timer.start(host, this.race.settings.startOffsetSeconds);
    this.camera?.beginTiming(this.timer);
    this.phase = 'running';
    this.requestWakeLock();
    this.emit();
  }

  cancelStart() {
    clearTimeout(this.countdownHandle);
    this.countdownHandle = null;
    stopMicrophone();
    this.timer.reset();
    this.phase = 'ready';
    this.emit();
  }

  record() {
    if (this.phase !== 'running' || !this.usesCamera || !this.camera) return;
    this.frames = 0;
    this.dropped = 0;
    this.camera.startRecording(this.race.id, this.race.mode);
    this.phase = 'recording';
    this.emit();
  }

  stop() {
    if (this.phase === 'armed' || this.phase === 'countdown') { this.cancelStart(); return; }
    if (this.phase !== 'running' && this.phase !== 'recording') return;
    this.timer.stop(hostNow());
    this.race.elapsedSeconds = this.timer.elapsed(hostNow());
    if (this.phase === 'recording') {
      this.phase = 'processing';
      this.camera.stopRecording();
    } else {
      this.phase = 'finished';
      this.camera?.stop();
      this.camera = null;
      this.persist();
    }
    stopMicrophone();
    this.releaseWakeLock();
    this.emit();
  }

  background() {
    this.foreground = false;
    if (this.phase === 'armed' || this.phase === 'countdown') this.cancelStart();
    if (this.phase === 'running' || this.phase === 'recording') {
      this.errorMessage = 'Course arrêtée : l’application est passée en arrière-plan. La capture ne continue pas écran verrouillé.';
      const wasRecording = this.phase === 'recording';
      this.stop();
      if (wasRecording) return; // la caméra s'arrête après la finalisation
    }
    if (this.phase !== 'processing') {
      this.camera?.stop();
      this.camera = null;
      this.cameraReady = false;
    }
    this.emit();
  }

  async resume() {
    this.foreground = true;
    if (this.closed) return;
    await this.prepare();
  }

  updateSettings(patch) {
    if (this.phase !== 'ready' && this.phase !== 'preparing') return;
    this.race.settings = { ...this.race.settings, ...patch };
    this.camera?.updateSettings(this.race.settings);
    this.persist();
    this.emit();
  }

  /** Nouvelle tentative : nouvelle course avec les mêmes réglages et participants. */
  async retry() {
    if (this.phase !== 'finished') return;
    await this.persist();
    const prev = this.race;
    this.race = newRace({
      name: prev.name, distance: prev.distance, mode: prev.mode,
      settings: { ...prev.settings }, participants: prev.participants.map((p) => ({ ...p })),
    });
    this.timer.reset();
    Object.assign(this, { selectedFrame: 0, frames: 0, dropped: 0, motion: 0, errorMessage: null, cameraReady: false, phase: 'preparing' });
    this.selectedParticipant = this.firstUnassigned();
    // L'écran remonte l'aperçu caméra puis appelle prepare().
    this.emit();
  }

  close() {
    this.closed = true;
    if (this.phase === 'armed' || this.phase === 'countdown') this.cancelStart();
    clearTimeout(this.countdownHandle);
    stopMicrophone();
    if (this.phase === 'recording') this.camera?.finishRecording(true).finally(() => this.camera?.stop());
    else this.camera?.stop();
    this.releaseWakeLock();
  }

  markManual() {
    if (this.phase !== 'running' || this.usesCamera) return;
    this.addResult(this.timer.elapsed(hostNow()), 'Manuel', null);
  }

  markFrame() {
    const stamp = this.currentStamp;
    if (!stamp) return;
    this.addResult(stamp.elapsedSeconds, this.race.mode === 'photo' ? 'Photo-finish' : 'Vidéo', this.selectedFrame);
  }

  selectFrame(i) {
    const n = this.race.capture?.frames?.length ?? 0;
    if (!n) return;
    this.selectedFrame = Math.max(0, Math.min(n - 1, Math.round(i)));
    this.emit();
  }

  addResult(time, source, frame) {
    if (!Number.isFinite(time) || time < 0) return;
    const results = this.race.results;
    if (this.phase === 'running' || this.phase === 'recording') this.race.elapsedSeconds = Math.max(this.race.elapsedSeconds, time);
    const id = this.selectedParticipant;
    const existing = id ? results.find((r) => r.participantID === id) : null;
    if (existing) Object.assign(existing, { elapsedSeconds: time, source, frameIndex: frame });
    else results.push(newResult({ participantID: id, elapsedSeconds: time, source, frameIndex: frame }));
    this.selectedParticipant = this.firstUnassigned();
    this.persist();
    this.emit();
  }

  removeResult(id) {
    this.race.results = this.race.results.filter((r) => r.id !== id);
    this.selectedParticipant = this.firstUnassigned();
    this.persist();
    this.emit();
  }

  editResult(id, { name, bib, lane, time }) {
    const r = this.race.results.find((x) => x.id === id);
    if (!r || !Number.isFinite(time) || time < 0) return;
    const p = r.participantID ? this.race.participants.find((x) => x.id === r.participantID) : null;
    if (p) Object.assign(p, { name, bib, lane });
    else if (name.trim()) {
      const np = newParticipant({ name, bib, lane });
      this.race.participants.push(np);
      r.participantID = np.id;
    }
    if (Math.abs(r.elapsedSeconds - time) > 0.000001) {
      r.elapsedSeconds = time;
      r.source = 'Corrigé manuellement';
    }
    this.persist();
    this.emit();
  }

  assignResult(id, participantID) {
    const r = this.race.results.find((x) => x.id === id);
    if (!r) return;
    const other = participantID ? this.race.results.find((x) => x.participantID === participantID && x.id !== id) : null;
    if (other) other.participantID = null;
    r.participantID = participantID || null;
    this.selectedParticipant = this.firstUnassigned();
    this.persist();
    this.emit();
  }

  async persist() {
    try { await saveRace(this.race); this.saveProblem = null; }
    catch (err) { this.saveProblem = `Sauvegarde impossible : ${err?.message ?? err}`; this.emit(); }
  }

  async requestWakeLock() {
    try { this.wakeLock = await navigator.wakeLock?.request('screen'); } catch { this.wakeLock = null; }
  }

  releaseWakeLock() {
    this.wakeLock?.release?.().catch(() => {});
    this.wakeLock = null;
  }

  handle(e) {
    switch (e.type) {
      case 'motion':
        this.motion = e.score;
        this.emit();
        break;
      case 'progress':
        this.motion = e.motion;
        if (this.phase === 'recording') { this.frames = e.frames; this.dropped = e.dropped; }
        this.emit();
        break;
      case 'crossing':
        if (this.phase === 'recording' || this.phase === 'processing') this.addResult(e.elapsed, 'Mouvement (estimation)', e.frame);
        break;
      case 'finished':
        if (this.phase === 'recording') {
          this.timer.stop(hostNow());
          this.race.elapsedSeconds = this.timer.elapsed(hostNow());
        }
        this.race.capture = e.manifest;
        this.phase = 'finished';
        this.selectedFrame = 0;
        this.camera?.stop();
        this.camera = null;
        this.cameraReady = false;
        this.releaseWakeLock();
        this.persist();
        this.emit();
        break;
      case 'interrupted':
        this.errorMessage = e.message;
        this.cameraReady = false;
        if (this.phase === 'armed' || this.phase === 'countdown') this.cancelStart();
        if (this.phase === 'running' || this.phase === 'recording') this.stop();
        this.emit();
        break;
      default:
    }
  }
}
