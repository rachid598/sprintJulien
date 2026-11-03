import { html, render, useEffect, useMemo, useState } from './views/common.js';
import { Home } from './views/home.js';
import { NewRace } from './views/newRace.js';
import { RaceScreen } from './views/raceScreen.js';
import { RaceController } from './raceController.js';
import { requestPersistence, getRace } from './services/storage.js';

function useInstall() {
  const [deferred, setDeferred] = useState(null);
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true
    || globalThis.Capacitor?.isNativePlatform?.();
  const ios = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  useEffect(() => {
    const onPrompt = (e) => { e.preventDefault(); setDeferred(e); };
    addEventListener('beforeinstallprompt', onPrompt);
    return () => removeEventListener('beforeinstallprompt', onPrompt);
  }, []);
  return {
    canInstall: !!deferred && !standalone,
    iosHint: ios && !standalone,
    prompt: async () => { deferred?.prompt(); await deferred?.userChoice; setDeferred(null); },
  };
}

function App() {
  const [route, setRoute] = useState({ name: 'home' });
  const install = useInstall();
  const ctl = useMemo(() => (route.name === 'race' ? new RaceController(route.race, { reopening: route.reopening }) : null), [route]);

  useEffect(() => { requestPersistence(); }, []);
  useEffect(() => { scrollTo(0, 0); }, [route]);

  if (route.name === 'new') {
    return html`<${NewRace} onCancel=${() => setRoute({ name: 'home' })}
      onCreate=${(race) => setRoute({ name: 'race', race, reopening: false })} />`;
  }
  if (route.name === 'race' && ctl) {
    return html`<${RaceScreen} key=${route.race.id} ctl=${ctl} onClose=${() => setRoute({ name: 'home' })} />`;
  }
  return html`<${Home} install=${install} onNew=${() => setRoute({ name: 'new' })}
    onOpen=${async (r) => setRoute({ name: 'race', race: (await getRace(r.id)) ?? r, reopening: true })} />`;
}

render(html`<${App} />`, document.getElementById('app'));

if ('serviceWorker' in navigator && isSecureContext && !globalThis.Capacitor?.isNativePlatform?.()) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
