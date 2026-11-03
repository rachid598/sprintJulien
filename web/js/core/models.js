// Modèles partagés : même structure que SprintTimerCore/Models.swift, pour que
// l'export JSON d'une course reste lisible des deux côtés.

export const FINISH_MODES = {
  photo: 'Photo-finish',
  video: 'Vidéo-finish',
  instant: 'Arrivée instantanée',
  stopwatch: 'Chronomètre',
};

export const START_MODES = {
  manual: 'Manuel',
  sound: 'Signal sonore',
  countdown: 'Compte à rebours',
  microphone: 'Détection du son',
};

export const DISTANCES = [30, 50, 100, 200, 400];

export function uuid() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  const b = new Uint8Array(16);
  globalThis.crypto.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export function defaultSettings() {
  return {
    linePosition: 0.5,
    stripWidth: 2,
    requestedFPS: 60,
    maxRecordingDuration: 60,
    startMode: 'manual',
    countdownSeconds: 3,
    // Positif : l'origine est reculée, le temps mesuré augmente.
    startOffsetSeconds: 0,
    microphoneThreshold: 0.35,
    motionThreshold: 0.12,
    motionCooldown: 1,
    regionWidth: 0.12,
    humanFilter: false,
    keepVideoFile: false,
    reviewHeight: 640,
  };
}

export function newParticipant(fields = {}) {
  return { id: uuid(), name: '', bib: '', lane: '', ...fields };
}

export function newResult(fields) {
  return {
    id: uuid(),
    participantID: null,
    source: 'manuel',
    frameIndex: null,
    createdAt: new Date().toISOString(),
    ...fields,
  };
}

export function newRace(fields = {}) {
  return {
    version: 1,
    id: uuid(),
    name: 'Nouvelle course',
    date: new Date().toISOString(),
    distance: 100,
    mode: 'photo',
    settings: defaultSettings(),
    participants: [],
    results: [],
    capture: null,
    elapsedSeconds: 0,
    ...fields,
  };
}

export function newManifest(fields) {
  return {
    version: 1,
    imageWidth: 0,
    imageHeight: 0,
    stripWidth: 2,
    frames: [],
    tiles: [],
    videoFile: null,
    droppedFrames: 0,
    requestedFPS: 60,
    actualFPS: 0,
    startHostSeconds: 0,
    startOffsetSeconds: 0,
    interrupted: false,
    warnings: [],
    ...fields,
  };
}

const clamp = (v, lo, hi, fallback) => (Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : fallback);

/** Normalise les réglages saisis avant de créer une course. */
export function sanitizeSettings(s) {
  const d = defaultSettings();
  return {
    ...d,
    ...s,
    linePosition: clamp(s.linePosition, 0.05, 0.95, d.linePosition),
    stripWidth: Math.round(clamp(s.stripWidth, 1, 16, d.stripWidth)),
    requestedFPS: [30, 60, 120, 240].includes(s.requestedFPS) ? s.requestedFPS : d.requestedFPS,
    maxRecordingDuration: clamp(s.maxRecordingDuration, 5, 120, d.maxRecordingDuration),
    startMode: s.startMode in START_MODES ? s.startMode : d.startMode,
    countdownSeconds: Math.round(clamp(s.countdownSeconds, 1, 60, d.countdownSeconds)),
    startOffsetSeconds: clamp(s.startOffsetSeconds, -10, 10, 0),
    microphoneThreshold: clamp(s.microphoneThreshold, 0.02, 0.95, d.microphoneThreshold),
    motionThreshold: clamp(s.motionThreshold, 0.01, 0.5, d.motionThreshold),
    motionCooldown: clamp(s.motionCooldown, 0.1, 5, d.motionCooldown),
    regionWidth: clamp(s.regionWidth, 0.02, 0.4, d.regionWidth),
    reviewHeight: [480, 640, 960].includes(s.reviewHeight) ? s.reviewHeight : d.reviewHeight,
    keepVideoFile: !!s.keepVideoFile,
    humanFilter: false,
  };
}
