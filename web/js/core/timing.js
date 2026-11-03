// Portage de TimingEngine.swift. Tous les instants proviennent de la même
// horloge monotone (performance.now() convertie en secondes).

export class TimingEngine {
  constructor() {
    this.reset();
  }

  reset() {
    this.state = 'idle';
    this.startHostSeconds = null;
    this.startEventHostSeconds = null;
    this.stoppedElapsedSeconds = 0;
  }

  /**
   * Un offset positif ajoute du temps : origine = événement − offset.
   * Un second départ est ignoré jusqu'à reset().
   */
  start(hostSeconds, offset = 0) {
    if (this.state !== 'idle' || !Number.isFinite(hostSeconds) || !Number.isFinite(offset)) return;
    const origin = hostSeconds - offset;
    if (!Number.isFinite(origin)) return;
    this.startEventHostSeconds = hostSeconds;
    this.startHostSeconds = origin;
    this.stoppedElapsedSeconds = 0;
    this.state = 'running';
  }

  stop(hostSeconds) {
    if (this.state !== 'running' || !Number.isFinite(hostSeconds)) return;
    if (this.startEventHostSeconds === null || hostSeconds < this.startEventHostSeconds) return;
    this.stoppedElapsedSeconds = this.elapsed(hostSeconds);
    this.state = 'stopped';
  }

  elapsed(hostSeconds) {
    if (this.state === 'stopped') return this.stoppedElapsedSeconds;
    if (this.state !== 'running' || this.startHostSeconds === null || !Number.isFinite(hostSeconds)) return 0;
    return Math.max(0, hostSeconds - this.startHostSeconds);
  }
}

/** Affichage arrondi au centième, virgule française, sans prétendre à cette précision. */
export function formatTime(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  return seconds.toFixed(2).replace('.', ',');
}

/** Horloge hôte monotone, en secondes. */
export const hostNow = () => performance.now() / 1000;
