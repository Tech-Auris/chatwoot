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

// A 3×5 pixel font, just the characters the call screen writes.
const FONT = {
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
};

// Width in pixels of `text` written `size` times bigger.
export const textWidth = (text, size = 1) =>
  text.length ? (text.length * 4 - 1) * size : 0;

function write(paint, text, x, y, color, size = 1) {
  [...text].forEach((char, i) => {
    const glyph = FONT[char];
    if (!glyph) return;
    glyph.forEach((row, gy) =>
      [...row].forEach((dot, gx) => {
        if (dot === '#') {
          paint(color, x + (i * 4 + gx) * size, y + gy * size, size, size);
        }
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

// Two cards and two lines being typed, with a blinking cursor.
function drawCards(paint, sx, sy, t) {
  paint(WHITE, sx + 4, sy + 5, 9, 5);
  paint(MINT, sx + 15, sy + 5, 9, 5);
  // A tiny trend inside the white card.
  [0, 1, 2, 3, 4, 5, 6].forEach(i => {
    const y = 8 - Math.round(1.5 + 1.5 * Math.sin(t / 4 + i));
    paint(SCREEN, sx + 5 + i, sy + y);
  });
  const step = t % 56;
  const first = Math.min(23, step);
  const second = Math.max(0, Math.min(19, step - 24));
  paint(SKY, sx + 4, sy + 13, first, 1);
  paint(SKY, sx + 4, sy + 16, second, 1);
  if (Math.floor(t / 4) % 2 === 0) {
    const typing = step < 24;
    paint(
      WHITE,
      sx + 4 + (typing ? first : second),
      sy + (typing ? 12 : 15),
      1,
      3
    );
  }
}

// A lead falling through the funnel; each stage lights up as it goes by.
const STAGES = [
  { x: 5, y: 5, w: 22, color: MINT },
  { x: 8, y: 8, w: 16, color: SKY },
  { x: 11, y: 11, w: 10, color: YELLOW },
  { x: 14, y: 14, w: 4, color: RED },
];
function drawFunnel(paint, sx, sy, t) {
  const fall = t % 26;
  const y = 3 + Math.floor(fall / 2);
  STAGES.forEach(stage => {
    const passing = y === stage.y || y === stage.y + 1;
    paint(
      passing ? WHITE : stage.color,
      sx + stage.x,
      sy + stage.y,
      stage.w,
      2
    );
  });
  if (y > 4 && y < 19) paint(WHITE, sx + 15, sy + y, 2, 1);
}

const SCREENS = [drawBars, drawCards, drawFunnel];

function drawMonitors(paint, { tick }) {
  ROWS.forEach((sy, row) =>
    COLUMNS.forEach((sx, column) => {
      paint(SCREEN, sx + AREA.x, sy + AREA.y, AREA.w, AREA.h);
      // The bottom row runs out of step with the top one.
      SCREENS[column](paint, sx, sy, tick + row * 13);
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

function drawCallScreen(paint, { now }) {
  const [call, ...before] = callsAt(now, 3);
  const blink = blinking(now);
  // Header: what each column is.
  paint(TEAL, 2, 2, 52, 5);
  write(paint, 'SENHA', 4, 2, WHITE);
  write(paint, 'SALA', 51 - textWidth('SALA'), 2, WHITE);
  // The ticket and the room, big.
  paint(blink ? TEAL : PALE, 2, 7, 52, 13);
  write(paint, call.ticket, 4, 9, blink ? WHITE : INK, 2);
  const room = String(call.room);
  write(paint, room, 51 - textWidth(room, 2), 9, blink ? WHITE : DARK_TEAL, 2);
  // The two tickets called before.
  paint(PALE, 2, 20, 52, 5);
  before.forEach((previous, i) => {
    write(paint, `${previous.ticket} ${previous.room}`, 4 + i * 26, 20, GRAY);
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
