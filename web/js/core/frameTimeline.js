// Portage de FrameTimeline.swift. Aucun FPS théorique n'est utilisé pour
// calculer un temps ; une image manquante reste un trou temporel.

export class FrameTimeline {
  constructor(frames) {
    this.frames = frames;
    let valid = true;
    let prev = null;
    for (const f of frames) {
      if (
        !Number.isFinite(f.presentationSeconds) || !Number.isFinite(f.hostSeconds) ||
        !Number.isFinite(f.elapsedSeconds) || f.elapsedSeconds < 0 || !(f.index >= 0)
      ) { valid = false; break; }
      if (prev && (
        f.index <= prev.index || f.presentationSeconds <= prev.presentationSeconds ||
        f.hostSeconds <= prev.hostSeconds || f.elapsedSeconds <= prev.elapsedSeconds
      )) { valid = false; break; }
      prev = f;
    }
    this.isValid = valid;
  }

  /** Position dans `frames` (pas FrameStamp.index). En cas d'égalité, garde l'image précédente. */
  nearestIndex(target) {
    const { frames } = this;
    if (!this.isValid || frames.length === 0 || !Number.isFinite(target)) return null;
    let low = 0;
    let high = frames.length;
    while (low < high) {
      const mid = low + ((high - low) >> 1);
      if (frames[mid].elapsedSeconds < target) low = mid + 1; else high = mid;
    }
    if (low === 0) return 0;
    if (low === frames.length) return frames.length - 1;
    const before = target - frames[low - 1].elapsedSeconds;
    const after = frames[low].elapsedSeconds - target;
    return before <= after ? low - 1 : low;
  }

  /** Position d'image correspondant à un pixel horizontal de la bande assemblée. */
  indexAtPixel(pixel, stripWidth) {
    if (!this.isValid || this.frames.length === 0 || !(stripWidth > 0) || !Number.isFinite(pixel) || pixel < 0) return null;
    if (pixel > this.frames.length * stripWidth) return null;
    return Math.min(this.frames.length - 1, Math.floor(pixel / stripWidth));
  }

  timeAtPixel(pixel, stripWidth) {
    const i = this.indexAtPixel(pixel, stripWidth);
    return i === null ? null : this.frames[i].elapsedSeconds;
  }

  get maxFrameGap() {
    if (!this.isValid || this.frames.length < 2) return null;
    let max = -Infinity;
    for (let i = 1; i < this.frames.length; i++) {
      max = Math.max(max, this.frames[i].hostSeconds - this.frames[i - 1].hostSeconds);
    }
    return max;
  }

  /** Cadence observée sur les horodatages, trames perdues incluses. */
  get effectiveFPS() {
    const { frames } = this;
    if (!this.isValid || frames.length < 2) return 0;
    return (frames.length - 1) / (frames[frames.length - 1].hostSeconds - frames[0].hostSeconds);
  }
}
