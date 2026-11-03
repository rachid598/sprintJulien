// Portage de ResultsManager.swift.

const isValidTime = (t) => Number.isFinite(t) && t >= 0;

/** Tri stable des temps valides ; les mesures invalides sont placées en fin. */
export function ranked(results) {
  return results
    .map((r, i) => [r, i])
    .sort(([a, ai], [b, bi]) => {
      const av = isValidTime(a.elapsedSeconds);
      const bv = isValidTime(b.elapsedSeconds);
      if (av !== bv) return av ? -1 : 1;
      if (av && a.elapsedSeconds !== b.elapsedSeconds) return a.elapsedSeconds - b.elapsedSeconds;
      return ai - bi;
    })
    .map(([r]) => r);
}

const quoted = (v) => `"${String(v).replaceAll('"', '""')}"`;

/** Préfixe d'une apostrophe les champs qui seraient lus comme formules. */
export function safeText(value) {
  const trimmed = value.replace(/^\s+/u, '');
  if (!trimmed) return value;
  return ['=', '+', '-', '@'].includes(trimmed[0]) ? `'${value}` : value;
}

function isoSeconds(dateLike) {
  const d = new Date(dateLike);
  return Number.isNaN(d.getTime()) ? '' : d.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** CSV RFC 4180, UTF-8, virgule et CRLF, secondes à six décimales. */
export function csv(race) {
  const header = ['Course', 'Date', 'Distance (m)', 'Rang', 'Dossard', 'Couloir', 'Participant', 'Temps (s)', 'Source'];
  const rows = [header.map(quoted).join(',')];
  const people = new Map();
  for (const p of race.participants) if (!people.has(p.id)) people.set(p.id, p);
  const date = isoSeconds(race.date);
  ranked(race.results).forEach((result, index) => {
    const person = result.participantID ? people.get(result.participantID) : undefined;
    const elapsed = isValidTime(result.elapsedSeconds) ? result.elapsedSeconds.toFixed(6) : '';
    const values = [
      safeText(race.name), date, Number.isFinite(race.distance) ? String(race.distance) : '', String(index + 1),
      safeText(person?.bib ?? ''), safeText(person?.lane ?? ''),
      safeText(person?.name ?? 'Non attribué'), elapsed, safeText(result.source ?? ''),
    ];
    rows.push(values.map(quoted).join(','));
  });
  return rows.join('\r\n') + '\r\n';
}

/** Libellé d'un résultat pour l'affichage. */
export function participantLabel(race, result, rank) {
  const p = result.participantID ? race.participants.find((x) => x.id === result.participantID) : null;
  if (!p) return `Arrivée ${rank}`;
  const extra = [p.bib && `n° ${p.bib}`, p.lane && `couloir ${p.lane}`].filter(Boolean).join(' · ');
  return extra ? `${p.name} (${extra})` : p.name;
}
