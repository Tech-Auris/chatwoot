// Variation of a card against the period before it, as a whole percent.
// Null when there is nothing to compare against.
export const variation = (total, previous) => {
  if (!previous) return null;
  return Math.round(((total - previous) / previous) * 100);
};

// "1 min 40 s", "6 min", "45 s" — the first response time of the page.
export const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) return '—';
  const total = Math.round(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  if (hours) return minutes ? `${hours} h ${minutes} min` : `${hours} h`;
  if (minutes) return secs ? `${minutes} min ${secs} s` : `${minutes} min`;
  return `${secs} s`;
};

// Where each value of a trend line sits in a `width` x `height` box. A flat
// series sits in the middle; a single point is drawn as a short flat line.
export const sparklinePoints = (values, width, height) => {
  if (!values.length) return [];
  const points = values.length === 1 ? [values[0], values[0]] : values;
  const max = Math.max(...points);
  const min = Math.min(...points);
  const spread = max - min;
  const step = width / (points.length - 1);
  const pad = 3;
  return points.map((value, index) => {
    const ratio = spread ? (value - min) / spread : 0.5;
    return { x: index * step, y: height - pad - ratio * (height - pad * 2) };
  });
};

export const sparklinePath = (values, width, height) =>
  sparklinePoints(values, width, height)
    .map(
      ({ x, y }, index) => `${index ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`
    )
    .join(' ');

const shortDate = (date, locale) =>
  date.toLocaleDateString(locale, { day: '2-digit', month: '2-digit' });

// What one point of a trend line covers, for its tooltip: "seg., 03/11" for a
// day, "03/11 – 09/11" for a week, "nov. de 2026" for a month. `nextStart` is
// where the following point begins (null for the last one, which ends now).
// The app's locale comes as "pt_BR"; Intl only takes "pt-BR".
export const bucketLabel = (start, nextStart, granularity, appLocale) => {
  const locale = appLocale?.replace('_', '-');
  const from = new Date(start * 1000);
  if (granularity === 'day') {
    return from.toLocaleDateString(locale, {
      weekday: 'short',
      day: '2-digit',
      month: '2-digit',
    });
  }
  if (granularity === 'week') {
    const to = nextStart ? new Date((nextStart - 1) * 1000) : new Date();
    return `${shortDate(from, locale)} – ${shortDate(to, locale)}`;
  }
  return from.toLocaleDateString(locale, { month: 'short', year: 'numeric' });
};
