// Portage de MotionDetectionService.swift. Différence moyenne normalisée
// entre deux échantillonnages d'une même zone. Deux trames calmes réarment le
// détecteur. Cela ne distingue pas une personne d'une ombre.

export class MotionDetector {
  constructor(threshold = 0.12, cooldown = 1) {
    this.threshold = threshold;
    this.cooldown = cooldown;
    this.reset();
  }

  reset() {
    this.previous = null;
    this.previousTimestamp = null;
    this.lastTriggerTimestamp = null;
    this.isArmed = true;
    this.calmFrames = 0;
  }

  /** @param {ArrayLike<number>} luminance valeurs 0…255 */
  process(luminance, timestamp) {
    if (!Number.isFinite(timestamp) || !luminance || luminance.length === 0) return { score: 0, triggered: false };
    const previous = this.previous;
    const previousTimestamp = this.previousTimestamp;
    this.previous = Uint8Array.from(luminance);
    this.previousTimestamp = timestamp;
    if (!previous || previous.length !== luminance.length || previousTimestamp === null || !(timestamp > previousTimestamp)) {
      this.isArmed = true;
      this.calmFrames = 0;
      // Une horloge remise à zéro ne peut pas garder l'ancienne temporisation.
      if (previousTimestamp !== null && timestamp <= previousTimestamp) this.lastTriggerTimestamp = null;
      return { score: 0, triggered: false };
    }
    let sum = 0;
    for (let i = 0; i < luminance.length; i++) sum += Math.abs(previous[i] - luminance[i]);
    const score = sum / (255 * luminance.length);
    const level = Number.isFinite(this.threshold) ? Math.min(1, Math.max(0.001, this.threshold)) : 0.12;
    const delay = Number.isFinite(this.cooldown) ? Math.max(0, this.cooldown) : 1;
    if (score < level * 0.5) {
      this.calmFrames += 1;
      if (this.calmFrames >= 2) this.isArmed = true;
      return { score, triggered: false };
    }
    this.calmFrames = 0;
    if (score < level || !this.isArmed) return { score, triggered: false };
    // Le front montant est consommé même pendant la temporisation : un
    // mouvement prolongé ne devient pas une seconde arrivée différée.
    this.isArmed = false;
    if (this.lastTriggerTimestamp !== null && timestamp - this.lastTriggerTimestamp < delay) {
      return { score, triggered: false };
    }
    this.lastTriggerTimestamp = timestamp;
    return { score, triggered: true };
  }
}

/** Luminance Rec. 601 d'un tampon RGBA. */
export function luminanceFromRGBA(rgba) {
  const out = new Uint8Array(rgba.length / 4);
  for (let i = 0, j = 0; j < out.length; i += 4, j++) {
    out[j] = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) / 1000;
  }
  return out;
}
