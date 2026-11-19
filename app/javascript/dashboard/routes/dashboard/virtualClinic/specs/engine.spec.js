import { describe, it, expect } from 'vitest';
import {
  CHARACTERS,
  FLOORS,
  ITEMS,
  PARTITION,
  SPRITE_PATHS,
  WORLD,
} from '../engine/layout';
import { hitTest } from '../engine/renderer';

const inside = (x, y) =>
  x >= 0 && y >= 0 && x <= WORLD.width && y <= WORLD.height;

describe('clinic layout', () => {
  it('keeps every piece and seat inside the 30×20 clinic', () => {
    expect(WORLD).toEqual({ width: 960, height: 640 });
    ITEMS.forEach(item => expect(inside(item.x, item.y)).toBe(true));
    Object.values(CHARACTERS).forEach(spot => {
      expect(inside(spot.x, spot.y + 64)).toBe(true);
      expect(inside(spot.bubble.x, spot.bubble.y)).toBe(true);
    });
  });

  it('covers the whole clinic with floor below the walls', () => {
    const area = FLOORS.reduce((sum, floor) => sum + floor.w * floor.h, 0);
    expect(area).toBe(WORLD.width * (WORLD.height - 64) - 448 * 64);
  });

  it('opens two passages between the wings', () => {
    expect(PARTITION.gaps).toHaveLength(2);
  });

  it('only asks the API for pack files in the approved folders', () => {
    SPRITE_PATHS.forEach(path =>
      expect(path).toMatch(/^[1-7]_[a-z_]+\/[0-9A-Za-z_]+\.png$/)
    );
  });
});

describe('hitTest', () => {
  it('finds the teammate under the pointer', () => {
    const { x, y } = CHARACTERS.secretary;
    expect(hitTest(x + 16, y + 40, ['secretary', 'manager'])).toBe('secretary');
    expect(hitTest(x + 16, y + 2, ['secretary', 'manager'])).toBeUndefined();
    expect(hitTest(x + 16, y + 40, ['manager'])).toBeUndefined();
  });
});
