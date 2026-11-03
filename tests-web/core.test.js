// Tests du cœur web, portés depuis Packages/SprintTimerCore/Tests.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TimingEngine, formatTime } from '../web/js/core/timing.js';
import { FrameTimeline } from '../web/js/core/frameTimeline.js';
import { MotionDetector, luminanceFromRGBA } from '../web/js/core/motion.js';
import { ranked, csv } from '../web/js/core/results.js';
import { newRace, newParticipant, newResult, newManifest, sanitizeSettings, defaultSettings } from '../web/js/core/models.js';
import { pdfString, resultsPDF } from '../web/js/core/pdf.js';

const near = (a, b, eps = 1e-7) => assert.ok(Math.abs(a - b) <= eps, `${a} ≉ ${b}`);

test('départ, arrêt et remise à zéro gardent une référence monotone', () => {
  const e = new TimingEngine();
  assert.equal(e.state, 'idle');
  assert.equal(e.elapsed(1234), 0);
  e.start(100);
  e.start(101);
  assert.equal(e.startHostSeconds, 100);
  near(e.elapsed(112.345), 12.345);
  e.stop(112.345);
  assert.equal(e.state, 'stopped');
  near(e.elapsed(999), 12.345);
  e.start(500);
  assert.equal(e.state, 'stopped');
  e.reset();
  assert.equal(e.startHostSeconds, null);
  e.start(500);
  assert.equal(e.elapsed(501), 1);
});

test('le décalage est appliqué une fois avec le signe documenté', () => {
  const e = new TimingEngine();
  e.start(100, 0.25);
  assert.equal(e.startEventHostSeconds, 100);
  assert.equal(e.startHostSeconds, 99.75);
  assert.equal(e.elapsed(110), 10.25);
  e.stop(110);
  assert.equal(e.elapsed(111), 10.25);
  e.reset();
  e.start(100, -0.25);
  assert.equal(e.elapsed(100.1), 0);
  assert.equal(e.elapsed(110), 9.75);
});

test('des entrées invalides ne démarrent ni n’arrêtent la course', () => {
  const e = new TimingEngine();
  e.start(NaN);
  e.start(1, Infinity);
  assert.equal(e.state, 'idle');
  e.start(10);
  e.stop(9);
  e.stop(Infinity);
  assert.equal(e.state, 'running');
  assert.equal(e.elapsed(NaN), 0);
  assert.equal(e.elapsed(9), 0);
});

test('affichage au centième avec virgule', () => {
  assert.equal(formatTime(1.25), '1,25');
  assert.equal(formatTime(9.999), '10,00');
  assert.equal(formatTime(60.01), '60,01');
  assert.equal(formatTime(-1), '—');
  assert.equal(formatTime(NaN), '—');
});

const frame = (index, elapsed) => ({ index, presentationSeconds: 100 + elapsed, hostSeconds: 100 + elapsed, elapsedSeconds: elapsed, motionScore: 0 });

test('un trou réel entre images est conservé dans la correspondance pixel → temps', () => {
  const t = new FrameTimeline([frame(0, 10), frame(1, 10.01), frame(2, 10.1)]);
  assert.ok(t.isValid);
  assert.equal(t.timeAtPixel(0, 2), 10);
  assert.equal(t.timeAtPixel(2.5, 2), 10.01);
  assert.equal(t.timeAtPixel(4, 2), 10.1);
  assert.equal(t.timeAtPixel(6, 2), 10.1);
  near(t.maxFrameGap, 0.09, 1e-6);
  near(t.effectiveFPS, 20, 1e-6);
  assert.equal(t.nearestIndex(10.06), 2);
  assert.equal(t.nearestIndex(-100), 0);
  assert.equal(t.nearestIndex(1000), 2);
  assert.equal(t.timeAtPixel(-1, 2), null);
  assert.equal(t.timeAtPixel(7, 2), null);
  assert.equal(t.timeAtPixel(0, 0), null);
  assert.equal(t.nearestIndex(NaN), null);
});

test('nearestIndex renvoie une position, pas un identifiant d’image', () => {
  const t = new FrameTimeline([frame(5, 1), frame(8, 2), frame(10, 3)]);
  assert.equal(t.nearestIndex(2), 1);
  assert.equal(t.nearestIndex(1.5), 0);
});

test('les chronologies mal formées sont rejetées sans être retriées', () => {
  for (const frames of [[frame(0, 2), frame(1, 1)], [frame(0, 1), frame(1, 1)], [frame(0, 1), frame(0, 2)], [frame(0, NaN)]]) {
    const t = new FrameTimeline(frames);
    assert.equal(t.isValid, false);
    assert.equal(t.nearestIndex(1), null);
    assert.equal(t.timeAtPixel(0, 2), null);
    assert.equal(t.maxFrameGap, null);
    assert.equal(t.effectiveFPS, 0);
    assert.equal(t.frames.length, frames.length);
  }
});

test('aucune cadence inventée pour zéro ou une image', () => {
  const empty = new FrameTimeline([]);
  assert.equal(empty.nearestIndex(0), null);
  assert.equal(empty.timeAtPixel(0, 1), null);
  assert.equal(empty.effectiveFPS, 0);
  const single = new FrameTimeline([frame(0, 4.12)]);
  assert.equal(single.timeAtPixel(0.5, 1), 4.12);
  assert.equal(single.effectiveFPS, 0);
  assert.equal(single.maxFrameGap, null);
});

test('scène statique, score normalisé et réarmement', () => {
  const d = new MotionDetector(0.1, 1);
  assert.equal(d.process([0, 0, 0, 0], 1).triggered, false);
  assert.equal(d.process([0, 0, 0, 0], 2).triggered, false);
  const r = d.process([255, 255, 255, 255], 3);
  assert.equal(r.score, 1);
  assert.equal(r.triggered, true);
  assert.equal(d.process([0, 0, 0, 0], 5).triggered, false);
  assert.equal(d.process([255, 255, 255, 255], 6).triggered, false);
});

test('réarmement calme et temporisation sans doublon différé', () => {
  const d = new MotionDetector(0.1, 2);
  d.process([0], 0);
  assert.equal(d.process([255], 1).triggered, true);
  d.process([255], 1.1);
  d.process([255], 1.2);
  assert.equal(d.isArmed, true);
  assert.equal(d.process([0], 1.3).triggered, false);
  assert.equal(d.isArmed, false);
  assert.equal(d.process([255], 4).triggered, false);
  d.process([255], 4.1);
  d.process([255], 4.2);
  assert.equal(d.process([0], 4.3).triggered, true);
});

test('mouvement partiel : différence moyenne', () => {
  const d = new MotionDetector(0.3);
  d.process([0, 0, 0, 0], 1);
  const r = d.process([255, 0, 0, 0], 2);
  assert.equal(r.score, 0.25);
  assert.equal(r.triggered, false);
});

test('changement de résolution et horloge qui recule : nouvelle référence', () => {
  const d = new MotionDetector();
  d.process([0], 10);
  assert.equal(d.process([255, 255], 11).triggered, false);
  assert.equal(d.process([0, 0], 9).triggered, false);
  assert.equal(d.process([255, 255], 10).triggered, true);
  d.reset();
  assert.equal(d.process([0, 0], 11).triggered, false);
  assert.equal(d.process([], 12).triggered, false);
  assert.equal(d.process([0, 0], NaN).triggered, false);
});

test('luminance Rec. 601', () => {
  assert.deepEqual([...luminanceFromRGBA(new Uint8Array([255, 255, 255, 255, 0, 0, 0, 255, 255, 0, 0, 255]))], [255, 0, 76]);
});

test('classement à pleine précision et égalités stables', () => {
  const first = newResult({ elapsedSeconds: 10.004 });
  const second = newResult({ elapsedSeconds: 10.003 });
  const tied = newResult({ elapsedSeconds: 10.003 });
  const invalid = newResult({ elapsedSeconds: -Infinity });
  assert.deepEqual(ranked([first, second, tied, invalid]).map((r) => r.id), [second.id, tied.id, first.id, invalid.id]);
});

test('CSV : guillemets, retours à la ligne et protection contre les formules', () => {
  const person = newParticipant({ name: '=HYPERLINK("https://example.org")\nÉlève', bib: '+2', lane: '3' });
  const race = newRace({
    name: 'Course, "EPS"', date: new Date(0).toISOString(), distance: 100, participants: [person],
    results: [newResult({ participantID: person.id, elapsedSeconds: 12.123456, source: '@capture' })],
  });
  const out = csv(race);
  assert.ok(out.includes('"Course, ""EPS"""'));
  assert.ok(out.includes('"\'=HYPERLINK(""https://example.org"")\nÉlève"'));
  assert.ok(out.includes('"\'+2"'));
  assert.ok(out.includes('"12.123456"'));
  assert.ok(out.includes('"\'@capture"'));
  assert.ok(out.endsWith('\r\n'));
  assert.ok(out.includes('1970-01-01T00:00:00Z'));
});

test('CSV : participants en double et arrivées non attribuées', () => {
  const p = newParticipant({ name: 'Élève' });
  const race = newRace({ name: ' \t=course', participants: [p, p], results: [newResult({ elapsedSeconds: 1 }), newResult({ elapsedSeconds: NaN })] });
  const out = csv(race);
  assert.ok(out.includes('"\' \t=course"'));
  assert.ok(out.includes('"Non attribué"'));
  assert.ok(!out.toLowerCase().includes('nan'));
});

test('aller-retour JSON : temps et métadonnées de capture conservés', () => {
  const person = newParticipant({ name: 'Élève', bib: '12', lane: '4' });
  const race = newRace({ name: '100 mètres', participants: [person] });
  race.settings.startMode = 'microphone';
  race.settings.startOffsetSeconds = 0.25;
  race.capture = newManifest({
    raceID: race.id, mode: 'photo', imageWidth: 2, imageHeight: 100, stripWidth: 2,
    frames: [{ index: 0, presentationSeconds: 1024.123456789, hostSeconds: 1024.123456789, elapsedSeconds: 12.123456789, motionScore: 0 }],
    tiles: [{ relativePath: 'tile-0.png', startFrame: 0, frameCount: 1, pixelWidth: 2, pixelHeight: 100 }],
    droppedFrames: 1, actualFPS: 120, startHostSeconds: 1012, startOffsetSeconds: 0.25, interrupted: true, warnings: ['Capture interrompue'],
  });
  race.results = [newResult({ participantID: person.id, elapsedSeconds: 12.123456789, source: 'photo', frameIndex: 0 })];
  const decoded = JSON.parse(JSON.stringify(race));
  assert.deepEqual(decoded, race);
  assert.equal(decoded.capture.frames[0].presentationSeconds, 1024.123456789);
});

test('les réglages saisis sont bornés', () => {
  const s = sanitizeSettings({ ...defaultSettings(), startOffsetSeconds: 99, stripWidth: 40, linePosition: NaN, requestedFPS: 77, startMode: 'x' });
  assert.equal(s.startOffsetSeconds, 10);
  assert.equal(s.stripWidth, 16);
  assert.equal(s.linePosition, 0.5);
  assert.equal(s.requestedFPS, 60);
  assert.equal(s.startMode, 'manual');
  assert.equal(s.humanFilter, false);
});

test('PDF : encodage WinAnsi, échappement et structure valide', () => {
  assert.equal(pdfString('Élève (A) \\ ’ €'), '(\xc9l\xe8ve \\(A\\) \\\\ \x92 \x80)');
  assert.equal(pdfString('日本'), '(??)');
  const p = newParticipant({ name: 'Élève' });
  const race = newRace({ name: 'Test', participants: [p], results: Array.from({ length: 40 }, (_, i) => newResult({ participantID: i ? null : p.id, elapsedSeconds: 10 + i / 10 })) });
  const bytes = resultsPDF(race);
  const text = Buffer.from(bytes).toString('latin1');
  assert.ok(text.startsWith('%PDF-1.4'));
  assert.ok(text.trimEnd().endsWith('%%EOF'));
  assert.ok(text.includes('/Count 2'));
  // Chaque entrée xref pointe sur le début de son objet.
  const xrefAt = Number(text.match(/startxref\n(\d+)/)[1]);
  assert.ok(text.slice(xrefAt).startsWith('xref'));
  const entries = text.slice(xrefAt).split('\n').slice(3).filter((l) => / 00000 n $/.test(l));
  entries.forEach((line, i) => assert.ok(text.slice(Number(line.slice(0, 10))).startsWith(`${i + 1} 0 obj`)));
  assert.ok(text.includes('(\xc9l\xe8ve)'));
});
