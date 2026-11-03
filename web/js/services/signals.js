// Signaux de départ : bip programmé et détection microphone (Web Audio).
// Les instants sont convertis vers performance.now() en secondes, la même
// horloge que les images de caméra.

let ctx = null;

function audioContext() {
  if (!ctx || ctx.state === 'closed') {
    const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!AC) throw new Error('Audio indisponible sur cet appareil.');
    ctx = new AC({ latencyHint: 'interactive' });
  }
  return ctx;
}

/** Convertit un instant de l'horloge audio en secondes performance.now(). */
function contextToHost(c, contextTime) {
  const ts = c.getOutputTimestamp?.();
  if (ts && Number.isFinite(ts.contextTime) && ts.performanceTime > 0) {
    return ts.performanceTime / 1000 + (contextTime - ts.contextTime);
  }
  return performance.now() / 1000 + (contextTime - c.currentTime);
}

/** À appeler depuis un geste utilisateur pour débloquer l'audio (iOS). */
export async function unlockAudio() {
  const c = audioContext();
  if (c.state === 'suspended') await c.resume();
  return c;
}

/**
 * Programme un bip et renvoie son instant programmé (s, horloge hôte).
 * Ce n'est pas l'instant où le son atteint le coureur.
 */
export async function playStartBeep(delay = 0.1) {
  const c = await unlockAudio();
  const when = c.currentTime + delay;
  const osc = c.createOscillator();
  const gain = c.createGain();
  osc.frequency.value = 1000;
  gain.gain.setValueAtTime(0, when);
  gain.gain.linearRampToValueAtTime(0.8, when + 0.004);
  gain.gain.setValueAtTime(0.8, when + 0.15);
  gain.gain.linearRampToValueAtTime(0, when + 0.16);
  osc.connect(gain).connect(c.destination);
  osc.start(when);
  osc.stop(when + 0.17);
  // Instant programmé, comme sur iOS : la latence de sortie se calibre avec
  // le décalage de départ.
  return contextToHost(c, when);
}

/** Petit bip de compte à rebours, sans valeur de mesure. */
export async function tick() {
  try {
    const c = await unlockAudio();
    const osc = c.createOscillator();
    const gain = c.createGain();
    osc.frequency.value = 660;
    gain.gain.value = 0.25;
    osc.connect(gain).connect(c.destination);
    osc.start();
    osc.stop(c.currentTime + 0.06);
  } catch { /* silencieux */ }
}

let micState = null;

/**
 * Arme la détection microphone. `onTrigger(hostSeconds)` reçoit l'instant du
 * premier échantillon dépassant le seuil ; `onLevel(peak)` environ 10 fois par seconde.
 */
export async function armMicrophone(threshold, onLevel, onTrigger) {
  stopMicrophone();
  const c = await unlockAudio();
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    video: false,
  });
  const source = c.createMediaStreamSource(stream);
  let node;
  let fired = false;
  const fire = (contextTime, peak) => {
    if (fired) return;
    fired = true;
    // La latence d'entrée du micro n'est pas compensée : à calibrer.
    onTrigger(contextToHost(c, contextTime), peak);
  };
  if (c.audioWorklet) {
    await c.audioWorklet.addModule(new URL('../audio-worklet.js', import.meta.url));
    node = new AudioWorkletNode(c, 'threshold-detector', { processorOptions: { threshold } });
    node.port.onmessage = ({ data }) => {
      if (data.type === 'level') onLevel(data.peak);
      else if (data.type === 'trigger') fire(data.contextTime, data.peak);
    };
    source.connect(node);
    // Une sortie muette garde le graphe actif sur certains navigateurs.
    const mute = c.createGain();
    mute.gain.value = 0;
    node.connect(mute).connect(c.destination);
  } else {
    // Repli : ScriptProcessor (moins précis, tampons plus longs).
    node = c.createScriptProcessor(512, 1, 1);
    let lastLevel = 0;
    node.onaudioprocess = (e) => {
      const data = e.inputBuffer.getChannelData(0);
      let peak = 0;
      let first = -1;
      for (let i = 0; i < data.length; i++) {
        const a = Math.abs(data[i]);
        if (a > peak) peak = a;
        if (first < 0 && a >= threshold) first = i;
      }
      if (e.playbackTime - lastLevel > 0.1) { lastLevel = e.playbackTime; onLevel(peak); }
      if (first >= 0) fire(e.playbackTime - (data.length - first) / c.sampleRate, peak);
    };
    source.connect(node);
    node.connect(c.destination);
  }
  micState = { stream, source, node };
}

export function stopMicrophone() {
  if (!micState) return;
  try { micState.source.disconnect(); micState.node.disconnect(); } catch { /* déjà déconnecté */ }
  micState.stream.getTracks().forEach((t) => t.stop());
  micState = null;
}
