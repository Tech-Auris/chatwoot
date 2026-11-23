// Places the appointments of one agenda column on the time grid. Positions are
// in minutes from midnight; appointments that overlap share the column width,
// each in its own `lane` out of `lanes`.
export const DEFAULT_DURATION = 30;
export const MIN_DURATION = 15;

const minutesOfDay = value => {
  const date = new Date(value);
  return date.getHours() * 60 + date.getMinutes();
};

export const spanOf = appointment => {
  const start = minutesOfDay(appointment.starts_at);
  const end = appointment.ends_at
    ? minutesOfDay(appointment.ends_at)
    : start + DEFAULT_DURATION;
  return { start, end: Math.max(end, start + MIN_DURATION) };
};

export const layoutColumn = appointments => {
  const items = appointments
    .map(appointment => ({ appointment, ...spanOf(appointment) }))
    .sort((a, b) => a.start - b.start || b.end - a.end);

  const placed = [];
  let cluster = [];
  let laneEnds = [];
  const closeCluster = () => {
    cluster.forEach(item => placed.push({ ...item, lanes: laneEnds.length }));
    cluster = [];
    laneEnds = [];
  };

  items.forEach(item => {
    if (cluster.length && item.start >= Math.max(...laneEnds)) closeCluster();
    let lane = laneEnds.findIndex(end => end <= item.start);
    if (lane === -1) lane = laneEnds.length;
    laneEnds[lane] = item.end;
    cluster.push({ ...item, lane });
  });
  closeCluster();
  return placed;
};

// The hours the grid shows: business hours, stretched to fit every appointment.
export const hourRange = (appointments, { first = 8, last = 18 } = {}) => {
  const spans = appointments.map(spanOf);
  const start = Math.min(first, ...spans.map(s => Math.floor(s.start / 60)));
  const end = Math.max(last, ...spans.map(s => Math.ceil(s.end / 60)));
  return { start, end: Math.min(end, 24) };
};
