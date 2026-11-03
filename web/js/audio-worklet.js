// Détecteur de seuil exécuté dans le fil audio temps réel.
// Renvoie l'instant (horloge audio) du premier échantillon au-dessus du seuil.

class ThresholdDetector extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.threshold = options.processorOptions?.threshold ?? 0.35;
    this.fired = false;
    this.lastLevel = 0;
    this.peak = 0;
  }

  process(inputs) {
    const channel = inputs[0]?.[0];
    if (!channel) return true;
    let peak = 0;
    let first = -1;
    for (let i = 0; i < channel.length; i++) {
      const a = Math.abs(channel[i]);
      if (a > peak) peak = a;
      if (first < 0 && a >= this.threshold) first = i;
    }
    this.peak = Math.max(this.peak, peak);
    // currentTime désigne le premier échantillon du bloc courant.
    if (currentTime - this.lastLevel > 0.1) {
      this.port.postMessage({ type: 'level', peak: this.peak });
      this.lastLevel = currentTime;
      this.peak = 0;
    }
    if (!this.fired && first >= 0) {
      this.fired = true;
      this.port.postMessage({ type: 'trigger', contextTime: currentTime + first / sampleRate, peak });
    }
    return true;
  }
}

registerProcessor('threshold-detector', ThresholdDetector);
