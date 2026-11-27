import { describe, it, expect } from 'vitest';
import {
  CALL_MS,
  CALL_SCREEN,
  CLOCK,
  callAt,
  callsAt,
  clockTime,
  drawLive,
  handEnd,
  linePixels,
  textWidth,
} from '../engine/livePieces';
import {
  DEFAULT_LAYOUT,
  ITEMS,
  LAYOUT_VERSION,
  applySaved,
  toSaved,
} from '../engine/layout';

// A canvas context that remembers the color of each pixel painted.
const fakeContext = () => {
  const pixels = {};
  return {
    pixels,
    fillStyle: null,
    fillRect(x, y, w, h) {
      for (let i = 0; i < w; i += 1) {
        for (let j = 0; j < h; j += 1)
          pixels[`${x + i},${y + j}`] = this.fillStyle;
      }
    },
  };
};

describe('recepção clock', () => {
  it('tells the time in the clinic time zone', () => {
    const now = new Date('2026-11-27T19:23:00Z');
    expect(clockTime(now, 'America/Sao_Paulo')).toEqual({
      hours: 16,
      minutes: 23,
    });
    expect(clockTime(now, 'America/Manaus')).toEqual({
      hours: 15,
      minutes: 23,
    });
  });

  it('draws the hands where the time points', () => {
    expect(handEnd(0, 7)).toEqual({ x: 13, y: 6 });
    expect(handEnd(0.25, 4)).toEqual({ x: 17, y: 13 });
    expect(linePixels({ x: 13, y: 13 }, { x: 13, y: 10 })).toEqual([
      [13, 13],
      [13, 12],
      [13, 11],
      [13, 10],
    ]);

    // 15:00 in São Paulo: the minute hand up, the hour hand right.
    const context = fakeContext();
    const item = { sprite: CLOCK, x: 100, y: 10 };
    drawLive(context, item, {
      now: new Date('2026-11-27T18:00:00Z'),
      timeZone: 'America/Sao_Paulo',
    });
    expect(context.pixels['113,16']).toBe('#2e324e');
    expect(context.pixels['117,23']).toBe('#2e324e');
    expect(context.pixels['113,23']).toBe('#e5566a');
  });
});

describe('sala de espera call screen', () => {
  it('calls the same tickets for everyone, one every 8 seconds', () => {
    expect(callAt(42)).toEqual(callAt(42));
    const [now, before] = callsAt(5 * CALL_MS + 10, 2);
    expect([now.index, before.index]).toEqual([5, 4]);
    expect(now.at).toBe(5 * CALL_MS);
    Array.from({ length: 50 }, (_, i) => callAt(1000 + i)).forEach(call => {
      expect(call.ticket).toMatch(/^[AP]\d{3}$/);
      expect(call.room).toBeGreaterThanOrEqual(1);
      expect(call.room).toBeLessThanOrEqual(6);
    });
  });

  it('writes the ticket on the TV screen', () => {
    expect(textWidth('A012', 2)).toBe(30);
    const context = fakeContext();
    drawLive(context, { sprite: CALL_SCREEN, x: 0, y: 0 }, { now: 3000 });
    const painted = Object.keys(context.pixels).map(key =>
      key.split(',').map(Number)
    );
    painted.forEach(([x, y]) => {
      expect(x).toBeGreaterThanOrEqual(2);
      expect(x).toBeLessThanOrEqual(53);
      expect(y).toBeGreaterThanOrEqual(2);
      expect(y).toBeLessThanOrEqual(24);
    });
  });

  it('leaves the other pieces alone', () => {
    const context = fakeContext();
    drawLive(context, { sprite: '4_copa/geladeira.png', x: 0, y: 0 }, {});
    expect(context.pixels).toEqual({});
  });
});

describe('marketing monitor wall', () => {
  it('moves the screens and keeps the frame', () => {
    const at = tick => {
      const context = fakeContext();
      drawLive(
        context,
        { sprite: '14_marketing/painel_monitores.png', x: 0, y: 0 },
        { tick }
      );
      return context.pixels;
    };
    expect(at(0)).not.toEqual(at(5));
    Object.keys(at(0)).forEach(key => {
      const [x, y] = key.split(',').map(Number);
      expect(x % 34).toBeGreaterThanOrEqual(2);
      expect(x % 34).toBeLessThanOrEqual(29);
      expect(y % 23).toBeGreaterThanOrEqual(4);
      expect(y % 23).toBeLessThanOrEqual(19);
    });
  });
});

describe('call screen in saved layouts', () => {
  const TV = '2_sala_de_espera/tv_parede.png';
  const tvs = layout => layout.items.filter(({ sprite }) => sprite === TV);
  const savedBefore = { items: ITEMS.filter(({ sprite }) => sprite !== TV) };

  it('comes with the default clinic', () => {
    expect(tvs(DEFAULT_LAYOUT)).toHaveLength(1);
  });

  it('is added to clinics saved before it existed, once', () => {
    expect(tvs(applySaved(savedBefore))).toHaveLength(1);
    expect(tvs(applySaved({ items: ITEMS }))).toHaveLength(1);
  });

  it('stays out once the clinic saved without it', () => {
    const saved = { ...savedBefore, version: LAYOUT_VERSION };
    expect(tvs(applySaved(saved))).toHaveLength(0);
    expect(toSaved(DEFAULT_LAYOUT).version).toBe(LAYOUT_VERSION);
  });
});
