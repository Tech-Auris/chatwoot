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
  pieColor,
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
    expect(textWidth('SALA')).toBe(15);
    const context = fakeContext();
    drawLive(context, { sprite: CALL_SCREEN, x: 0, y: 0 }, { now: 3000 });
    const painted = Object.keys(context.pixels).map(key =>
      key.split(',').map(Number)
    );
    painted.forEach(([x, y]) => {
      expect(x).toBeGreaterThanOrEqual(2);
      expect(x).toBeLessThanOrEqual(53);
      expect(y).toBeGreaterThanOrEqual(2);
      expect(y).toBeLessThanOrEqual(32);
    });
  });

  it('leaves the other pieces alone', () => {
    const context = fakeContext();
    drawLive(context, { sprite: '4_copa/geladeira.png', x: 0, y: 0 }, {});
    expect(context.pixels).toEqual({});
  });
});

describe('marketing monitor wall', () => {
  const at = tick => {
    const context = fakeContext();
    drawLive(
      context,
      { sprite: '14_marketing/painel_monitores.png', x: 0, y: 0 },
      { tick }
    );
    return context.pixels;
  };
  // The pixels of one screen (column, row) of the wall.
  const screen = (pixels, column, row) =>
    Object.fromEntries(
      Object.entries(pixels).filter(([key]) => {
        const [x, y] = key.split(',').map(Number);
        return Math.floor(x / 34) === column && Math.floor(y / 23) === row;
      })
    );

  it('moves the bars and keeps the funnels and the pie still', () => {
    [
      [0, 0],
      [1, 0],
      [2, 1],
    ].forEach(([column, row]) =>
      expect(screen(at(0), column, row)).not.toEqual(screen(at(5), column, row))
    );
    [
      [2, 0],
      [0, 1],
      [1, 1],
    ].forEach(([column, row]) =>
      expect(screen(at(0), column, row)).toEqual(screen(at(5), column, row))
    );
  });

  it('cuts the pie into its slices, clockwise from the top', () => {
    expect(pieColor(1, -4)).toBe('#8fd6cd');
    expect(pieColor(-4, 1)).toBe('#b9d4ff');
    expect(pieColor(-2, -5)).toBe('#e5566a');
    expect(pieColor(6, 6)).toBeNull();
  });

  it('keeps the frame', () => {
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
  const TV = '2_sala_de_espera/tv_pedestal.png';
  const ARMCHAIRS = '2_sala_de_espera/poltronas_verdes_dupla.png';
  const count = (layout, sprite) =>
    layout.items.filter(item => item.sprite === sprite).length;
  // A clinic saved before the TV: the green armchairs where the TV is now.
  const armchairs = { sprite: ARMCHAIRS, x: 292, y: 352 };
  const savedBefore = {
    items: [...ITEMS.filter(({ sprite }) => sprite !== TV), armchairs],
  };

  it('stands where the green armchairs were in the default clinic', () => {
    expect(count(DEFAULT_LAYOUT, TV)).toBe(1);
    expect(count(DEFAULT_LAYOUT, ARMCHAIRS)).toBe(0);
  });

  it('takes the place of the armchairs in clinics saved before it, once', () => {
    const layout = applySaved(savedBefore);
    expect(count(layout, TV)).toBe(1);
    expect(count(layout, ARMCHAIRS)).toBe(0);
    expect(count(applySaved({ items: ITEMS }), TV)).toBe(1);
  });

  it('leaves armchairs the clinic moved elsewhere', () => {
    const moved = { ...armchairs, x: 100 };
    const layout = applySaved({ items: [moved] });
    expect(layout.items).toContainEqual(moved);
    expect(count(layout, TV)).toBe(1);
  });

  it('keeps what the clinic chose once it saved this version', () => {
    const saved = { ...savedBefore, version: LAYOUT_VERSION };
    expect(count(applySaved(saved), TV)).toBe(0);
    expect(count(applySaved(saved), ARMCHAIRS)).toBe(1);
    expect(toSaved(DEFAULT_LAYOUT).version).toBe(LAYOUT_VERSION);
  });
});
