// Pieces of the clinic that change while you look at them: the marketing
// monitor wall, the recepção clock and the sala de espera call screen. The
// art stays as it is; after the piece is drawn, its screen (or clock face)
// is drawn again on top, pixel by pixel, in the colors of the art.
// Coordinates are pixels of the sprite cropped to its outline.

const MONITORS = '14_marketing/painel_monitores.png';
export const CLOCK = '1_recepcao/relogio.png';
export const CALL_SCREEN = '2_sala_de_espera/tv_pedestal.png';

// The colors of the art.
const INK = '#2e324e';
const SCREEN = '#4f88d6';
const WHITE = '#ffffff';
const MINT = '#8fd6cd';
const SKY = '#b9d4ff';
const YELLOW = '#ffcf5a';
const RED = '#e5566a';
const TEAL = '#62bdb3';
const PALE = '#dff3f1';
const GRAY = '#8a91ad';
const DARK_TEAL = '#4a9e96';

const painter =
  (context, item) =>
  (color, x, y, w = 1, h = 1) => {
    context.fillStyle = color;
    context.fillRect(item.x + x, item.y + y, w, h);
  };

// Pixel fonts with just the characters the call screen writes: a 3×5 one
// for labels and the footer, a 5×7 one for the ticket and the room.
const SMALL = {
  width: 3,
  glyphs: {
    0: ['###', '#.#', '#.#', '#.#', '###'],
    1: ['.#.', '##.', '.#.', '.#.', '###'],
    2: ['###', '..#', '###', '#..', '###'],
    3: ['###', '..#', '.##', '..#', '###'],
    4: ['#.#', '#.#', '###', '..#', '..#'],
    5: ['###', '#..', '###', '..#', '###'],
    6: ['###', '#..', '###', '#.#', '###'],
    7: ['###', '..#', '.#.', '.#.', '.#.'],
    8: ['###', '#.#', '###', '#.#', '###'],
    9: ['###', '#.#', '###', '..#', '###'],
    A: ['.#.', '#.#', '###', '#.#', '#.#'],
    E: ['###', '#..', '##.', '#..', '###'],
    H: ['#.#', '#.#', '###', '#.#', '#.#'],
    L: ['#..', '#..', '#..', '#..', '###'],
    N: ['##.', '#.#', '#.#', '#.#', '#.#'],
    P: ['##.', '#.#', '##.', '#..', '#..'],
    S: ['.##', '#..', '.#.', '..#', '##.'],
  },
};
const BIG = {
  width: 5,
  glyphs: {
    0: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    1: ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    2: ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
    3: ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
    4: ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
    5: ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
    6: ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
    7: ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
    8: ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
    9: ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
    A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    P: ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  },
};

// Width in pixels of `text` in `font`.
export const textWidth = (text, font = SMALL) =>
  text.length ? text.length * (font.width + 1) - 1 : 0;

function write(paint, text, x, y, color, font = SMALL) {
  [...text].forEach((char, i) => {
    font.glyphs[char]?.forEach((row, gy) =>
      [...row].forEach((dot, gx) => {
        if (dot === '#') paint(color, x + i * (font.width + 1) + gx, y + gy);
      })
    );
  });
}

// ---- The marketing monitor wall: 3 × 2 screens -------------------------

// Each screen's content area (below the title bar and its three dots).
const AREA = { x: 2, y: 4, w: 28, h: 16 };
const COLUMNS = [0, 34, 68];
const ROWS = [0, 23];

// Bars going up and down; the yellow one grows to the top and starts over.
function drawBars(paint, sx, sy, t) {
  [5, 10, 15, 20].forEach((x, i) => {
    const h = 7 + Math.round(4 * Math.sin(t / 7 + i * 1.7));
    paint(SKY, sx + x, sy + 18 - h, 3, h);
  });
  const h = 2 + (Math.floor(t / 3) % 12);
  paint(YELLOW, sx + 25, sy + 18 - h, 3, h);
}

// The same, lying down: bars growing to the right from an axis.
function drawBarsAcross(paint, sx, sy, t) {
  paint(SKY, sx + 4, sy + 5, 1, 13);
  [6, 9, 12].forEach((y, i) => {
    const w = 12 + Math.round(6 * Math.sin(t / 7 + i * 1.7));
    paint(SKY, sx + 5, sy + y, w, 2);
  });
  const w = 3 + (Math.floor(t / 3) % 20);
  paint(YELLOW, sx + 5, sy + 15, w, 2);
}

// Funnels and the pie stand still: they show where the leads end up.
const STAGES = [
  { x: 5, y: 5, w: 22, color: MINT },
  { x: 8, y: 8, w: 16, color: SKY },
  { x: 11, y: 11, w: 10, color: YELLOW },
  { x: 14, y: 14, w: 4, color: RED },
];
function drawFunnel(paint, sx, sy) {
  STAGES.forEach(stage =>
    paint(stage.color, sx + stage.x, sy + stage.y, stage.w, 2)
  );
}

// The funnel lying down: stages narrowing from left to right.
const COLUMN_STAGES = [
  { x: 4, y: 6, h: 12, color: MINT },
  { x: 10, y: 8, h: 8, color: SKY },
  { x: 16, y: 10, h: 4, color: YELLOW },
  { x: 22, y: 11, h: 2, color: RED },
];
function drawFunnelAcross(paint, sx, sy) {
  COLUMN_STAGES.forEach(stage =>
    paint(stage.color, sx + stage.x, sy + stage.y, 5, stage.h)
  );
}

// A pie (45% / 30% / 15% / 10%, clockwise from the top) and its legend.
const SLICES = [
  { until: 0.45, color: MINT },
  { until: 0.75, color: SKY },
  { until: 0.9, color: YELLOW },
  { until: 1, color: RED },
];
const PIE = { x: 10, y: 11, radius: 6 };
export function pieColor(dx, dy) {
  if (dx * dx + dy * dy > PIE.radius * (PIE.radius + 0.8)) return null;
  const turn = (Math.atan2(dx, -dy) / (2 * Math.PI) + 1) % 1;
  return SLICES.find(slice => turn < slice.until).color;
}
function drawPie(paint, sx, sy) {
  for (let dy = -PIE.radius; dy <= PIE.radius; dy += 1) {
    for (let dx = -PIE.radius; dx <= PIE.radius; dx += 1) {
      const color = pieColor(dx, dy);
      if (color) paint(color, sx + PIE.x + dx, sy + PIE.y + dy);
    }
  }
  SLICES.slice(0, 3).forEach(({ color }, i) => {
    paint(color, sx + 20, sy + 7 + i * 3, 2, 2);
    paint(WHITE, sx + 23, sy + 7 + i * 3, 4, 1);
  });
}

// Top row: bars lying down, bars standing up, the funnel; bottom row: the
// funnel lying down, the pie, bars lying down again.
const SCREENS = [
  [drawBarsAcross, drawBars, drawFunnel],
  [drawFunnelAcross, drawPie, drawBarsAcross],
];

function drawMonitors(paint, { tick }) {
  ROWS.forEach((sy, row) =>
    COLUMNS.forEach((sx, column) => {
      paint(SCREEN, sx + AREA.x, sy + AREA.y, AREA.w, AREA.h);
      // The bottom row runs out of step with the top one.
      SCREENS[row][column](paint, sx, sy, tick + row * 13);
    })
  );
}

// ---- The recepção clock -----------------------------------------------

const CENTER = { x: 13, y: 13 };
// Where the art draws its own hands (12 and 3 o'clock).
const ART_HANDS = [
  ...[6, 7, 8, 9, 10, 11, 12].map(y => [CENTER.x, y]),
  ...[14, 15, 16, 17, 18].map(x => [x, CENTER.y]),
];

// The pixels of a straight line (Bresenham), from `from` to `to`.
export function linePixels(from, to) {
  const pixels = [];
  let { x, y } = from;
  const dx = Math.abs(to.x - x);
  const dy = -Math.abs(to.y - y);
  const stepX = x < to.x ? 1 : -1;
  const stepY = y < to.y ? 1 : -1;
  let error = dx + dy;
  for (;;) {
    pixels.push([x, y]);
    if (x === to.x && y === to.y) return pixels;
    const double = 2 * error;
    if (double >= dy) {
      error += dy;
      x += stepX;
    }
    if (double <= dx) {
      error += dx;
      y += stepY;
    }
  }
}

// The end of a hand `length` pixels long pointing at `turn` (0–1 of a lap).
export const handEnd = (turn, length) => ({
  x: CENTER.x + Math.round(length * Math.sin(turn * 2 * Math.PI)),
  y: CENTER.y - Math.round(length * Math.cos(turn * 2 * Math.PI)),
});

const formatters = {};
// Hours and minutes now in `timeZone` (the clinic's).
export function clockTime(now, timeZone) {
  formatters[timeZone] ||= new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: 'numeric',
    minute: 'numeric',
    hourCycle: 'h23',
  });
  const parts = formatters[timeZone].formatToParts(now);
  const part = type => Number(parts.find(p => p.type === type).value);
  return { hours: part('hour'), minutes: part('minute') };
}

function drawClock(paint, { now, timeZone }) {
  const { hours, minutes } = clockTime(now, timeZone);
  ART_HANDS.forEach(([x, y]) => paint(WHITE, x, y));
  const minute = handEnd(minutes / 60, 7);
  const hour = handEnd(((hours % 12) + minutes / 60) / 12, 4);
  [...linePixels(CENTER, minute), ...linePixels(CENTER, hour)].forEach(
    ([x, y]) => paint(INK, x, y)
  );
  paint(RED, CENTER.x, CENTER.y);
}

// ---- The sala de espera call screen --------------------------------------

// A new ticket is called every 8 seconds. The calls come from the clock, so
// everyone with the clinic open sees the same ticket at the same time.
export const CALL_MS = 8000;
const ROOMS = 6;

// The call number `index` (counted from the epoch, every CALL_MS):
// `{ ticket: 'A012', room: 3, at }`, 1 in 4 of them preferential ("P").
export function callAt(index) {
  const hash = Math.abs(Math.imul(index, 2654435761));
  const number = String((index % 300) + 1).padStart(3, '0');
  return {
    index,
    ticket: `${hash % 4 === 0 ? 'P' : 'A'}${number}`,
    room: 1 + (hash % ROOMS),
    at: index * CALL_MS,
  };
}

// The call on the screen at `now` and the `count` before it, newest first.
export const callsAt = (now, count = 1) => {
  const current = Math.floor(now / CALL_MS);
  return Array.from({ length: count }, (_, i) => callAt(current - i));
};

// The screen blinks for a moment when a new ticket is called.
const blinking = now => {
  const since = now % CALL_MS;
  return since < 1500 && Math.floor(since / 250) % 2 === 0;
};

// The screen (inside the frame) spans x 2–53 and y 2–32 of the sprite.
function drawCallScreen(paint, { now }) {
  const [call, ...before] = callsAt(now, 3);
  const blink = blinking(now);
  // Header: what each column is.
  paint(TEAL, 2, 2, 52, 5);
  write(paint, 'SENHA', 4, 2, WHITE);
  write(paint, 'SALA', 51 - textWidth('SALA'), 2, WHITE);
  // The ticket and the room.
  paint(blink ? TEAL : PALE, 2, 7, 52, 15);
  write(paint, call.ticket, 4, 11, blink ? WHITE : INK, BIG);
  const room = String(call.room);
  write(
    paint,
    room,
    52 - textWidth(room, BIG),
    11,
    blink ? WHITE : DARK_TEAL,
    BIG
  );
  // Footer, under a line: the two tickets called before.
  paint(TEAL, 2, 22, 52, 1);
  paint(PALE, 2, 23, 52, 10);
  before.forEach((previous, i) => {
    write(paint, `${previous.ticket} ${previous.room}`, 4 + i * 26, 25, GRAY);
  });
}

const LIVE = {
  [MONITORS]: drawMonitors,
  [CLOCK]: drawClock,
  [CALL_SCREEN]: drawCallScreen,
};

export const isLive = sprite => Boolean(LIVE[sprite]);

// Draws the moving part of a live piece over it. `scene` is
// `{ tick, now, timeZone }`: the map tick (100 ms), the time in ms and the
// clinic's time zone.
export function drawLive(context, item, scene) {
  LIVE[item.sprite]?.(painter(context, item), scene);
}
