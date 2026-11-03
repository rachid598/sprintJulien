// Test de bout en bout de la PWA dans Chromium avec caméra et micro simulés.
// Usage : npm run e2e   (SCREENSHOTS=1 pour enregistrer des captures d'écran)
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import { startServer } from './serve-web.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const port = 8765;
const base = `http://localhost:${port}/`;
const shots = process.env.SCREENSHOTS ? new URL('../docs/screenshots/', import.meta.url).pathname : null;
if (shots) mkdirSync(shots, { recursive: true });

const server = await startServer(port);
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'],
});
const context = await browser.newContext({
  viewport: { width: 390, height: 844 }, deviceScaleFactor: shots ? 2 : 1, isMobile: true, hasTouch: true,
  permissions: ['camera', 'microphone'], acceptDownloads: true, colorScheme: 'dark', locale: 'fr-FR',
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
const shot = (name) => shots && page.screenshot({ path: `${shots}web-${name}.png` });
const step = (name) => console.log(`• ${name}`);

async function newRace(name, mode, participants = []) {
  await page.getByTestId('new-race').click();
  await page.getByTestId('race-name').fill(name);
  await page.getByTestId('race-mode').selectOption(mode);
  for (const p of participants) {
    await page.getByTestId('add-participant').click();
    await page.getByPlaceholder('Nom du participant').last().fill(p);
  }
  await page.getByTestId('prepare').click();
}

async function captureRace(name, mode, seconds = 2.5) {
  await newRace(name, mode, ['Léa', 'Noah']);
  await page.getByTestId('start').waitFor();
  await page.waitForFunction(() => !document.querySelector('[data-testid=start]')?.disabled, null, { timeout: 15000 });
  if (mode === 'photo') await shot('ready');
  await page.getByTestId('start').click();
  await page.getByTestId('record').click();
  await page.waitForTimeout(seconds * 1000);
  await page.getByTestId('finish-capture').click();
  await page.getByTestId('retry').waitFor({ timeout: 20000 });
}

const raceDoc = (name) => page.evaluate(async (n) => {
  const { listRaces } = await import('./js/services/storage.js');
  return (await listRaces()).find((r) => r.name === n);
}, name);

try {
  await page.goto(base);
  await page.getByTestId('new-race').waitFor();

  step('Chronomètre : départ manuel, deux arrivées, export CSV');
  await newRace('Chrono 50 m', 'stopwatch', ['Léa', 'Noah']);
  await page.getByTestId('start').click();
  await page.waitForTimeout(400);
  await page.getByTestId('mark').click();
  await page.waitForTimeout(250);
  await page.getByTestId('mark').click();
  await page.getByTestId('stop').click();
  await page.locator('[data-testid=results] li').nth(1).waitFor();
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByTestId('export-csv').click()]);
  const csvText = await (await import('node:fs/promises')).readFile(await download.path(), 'utf8');
  assert.match(csvText, /"Chrono 50 m",.*"1",.*"Léa","0\.\d{6}","Manuel"/);
  assert.match(csvText, /"2",.*"Noah"/);
  await shot('stopwatch-results');
  let doc = await raceDoc('Chrono 50 m');
  assert.equal(doc.results.length, 2);
  assert.ok(doc.results[1].elapsedSeconds > doc.results[0].elapsedSeconds);
  await page.getByTestId('back').click();

  step('Photo-finish : capture, bandes, sélection et marquage');
  await captureRace('Photo 100 m', 'photo');
  await page.getByTestId('photo-strip').locator('img').first().waitFor();
  const box = await page.getByTestId('photo-strip').boundingBox();
  await page.mouse.click(box.x + box.width * 0.6, box.y + box.height / 2);
  await page.getByTestId('next-frame').click();
  await page.getByTestId('mark-frame').click();
  await page.locator('[data-testid=results] li').first().waitFor();
  await page.evaluate(() => scrollTo(0, document.querySelector('[data-testid=photo-strip]').getBoundingClientRect().top + scrollY - 70));
  await shot('photo-finish');
  const png = await page.evaluate(async () => {
    const { photoFinishPNG } = await import('./js/services/exporter.js');
    const { listRaces } = await import('./js/services/storage.js');
    const race = (await listRaces()).find((r) => r.name === 'Photo 100 m');
    const blob = await photoFinishPNG(race);
    const bmp = await createImageBitmap(blob);
    return [blob.type, bmp.width, bmp.height];
  });
  assert.equal(png[0], 'image/png');
  assert.ok(png[1] > 0 && png[2] > 56, `PNG annoté inattendu : ${png}`);
  doc = await raceDoc('Photo 100 m');
  const cap = doc.capture;
  assert.ok(cap.frames.length > 30, `trop peu d'images : ${cap.frames.length}`);
  assert.ok(cap.tiles.length >= 1);
  assert.equal(cap.tiles.reduce((s, t) => s + t.frameCount, 0), cap.frames.length);
  for (let i = 1; i < cap.frames.length; i++) {
    assert.ok(cap.frames[i].hostSeconds > cap.frames[i - 1].hostSeconds);
    assert.ok(cap.frames[i].elapsedSeconds > cap.frames[i - 1].elapsedSeconds);
  }
  const marked = doc.results[0];
  assert.equal(marked.source, 'Photo-finish');
  assert.equal(marked.elapsedSeconds, cap.frames[marked.frameIndex].elapsedSeconds);
  console.log(`  ${cap.frames.length} images, ${cap.actualFPS.toFixed(1)} i/s mesurés, horodatage : ${cap.timestampSource}, ${cap.tiles.length} tuile(s)`);
  await page.getByTestId('back').click();

  step('Vidéo-finish : images de contrôle et marquage image par image');
  await captureRace('Vidéo 50 m', 'video');
  await page.getByTestId('review-frame').waitFor();
  await page.getByTestId('next-frame').click();
  await page.getByTestId('next-frame').click();
  await page.waitForFunction(() => !document.querySelector('[data-testid=mark-frame]').disabled);
  await page.getByTestId('mark-frame').click();
  await page.locator('[data-testid=results] li').first().waitFor();
  await shot('video-finish');
  doc = await raceDoc('Vidéo 50 m');
  assert.equal(doc.results[0].frameIndex, 2);
  assert.equal(doc.results[0].elapsedSeconds, doc.capture.frames[2].elapsedSeconds);
  const stored = await page.evaluate(async (id) => {
    const { getFile } = await import('./js/services/storage.js');
    const b = await getFile(`${id}/f-2.jpg`);
    return b ? [b.type, b.size] : null;
  }, doc.id);
  assert.equal(stored?.[0], 'image/jpeg');
  console.log(`  ${doc.capture.frames.length} images JPEG ${doc.capture.imageWidth}×${doc.capture.imageHeight}`);
  await page.getByTestId('back').click();

  step('Arrivée instantanée : détection de mouvement et nouvelle tentative');
  await captureRace('Instant 30 m', 'instant', 3);
  doc = await raceDoc('Instant 30 m');
  assert.ok(doc.capture.frames.length > 30);
  for (const r of doc.results) {
    assert.equal(r.source, 'Mouvement (estimation)');
    assert.equal(r.elapsedSeconds, doc.capture.frames[r.frameIndex].elapsedSeconds);
  }
  console.log(`  ${doc.results.length} détection(s) sur la mire animée`);
  await page.getByTestId('retry').click();
  await page.getByTestId('start').waitFor();
  await page.getByTestId('back').click();

  step('Historique, réouverture et modification d’un résultat');
  await page.getByText('Chrono 50 m').click();
  await page.locator('[data-testid=results] .result').first().click();
  await page.getByTestId('edit-name').fill('Léa Martin');
  await page.getByTestId('edit-save').click();
  await page.getByText('Léa Martin').waitFor();
  await page.getByTestId('back').click();
  await page.getByText('Photo 100 m').waitFor();
  await shot('home');

  step('Hors ligne : rechargement depuis le service worker');
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await page.evaluate(() => navigator.serviceWorker.ready);
  await context.setOffline(true);
  await page.reload();
  await page.getByTestId('new-race').waitFor();
  await page.getByText('Photo 100 m').waitFor();
  await context.setOffline(false);

  assert.deepEqual(errors, []);
  console.log('E2E OK');
} finally {
  await browser.close();
  server.close();
}
