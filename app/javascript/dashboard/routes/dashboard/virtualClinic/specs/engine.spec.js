import { describe, it, expect } from 'vitest';
import {
  BACK_DOOR,
  CHARACTERS,
  DEFAULT_LAYOUT,
  ENTRANCE,
  FLOORS,
  ITEMS,
  SPRITE_PATHS,
  WORLD,
} from '../engine/layout';
import { hitTest } from '../engine/renderer';
import {
  CELL,
  COLUMNS,
  buildCollision,
  cellOf,
  feetOf,
} from '../engine/collision';
import { findPath } from '../engine/pathfinding';
import { nearestFree } from '../engine/trips';

const inside = (x, y) =>
  x >= 0 && y >= 0 && x <= WORLD.width && y <= WORLD.height;

describe('clinic layout', () => {
  it('keeps every piece and seat inside the 40×20 clinic', () => {
    expect(WORLD).toEqual({ width: 1280, height: 640 });
    ITEMS.forEach(item => expect(inside(item.x, item.y)).toBe(true));
    Object.values(CHARACTERS).forEach(spot => {
      expect(inside(spot.x, spot.y + 64)).toBe(true);
    });
  });

  it('covers the whole clinic with floor below the walls', () => {
    const area = FLOORS.reduce((sum, floor) => sum + floor.w * floor.h, 0);
    expect(area).toBe(WORLD.width * (WORLD.height - 64) - 640 * 64);
  });

  it('only asks the API for pack files in the approved folders', () => {
    SPRITE_PATHS.forEach(path =>
      expect(path).toMatch(/^([1-9]|1[04])_[a-z_]+\/[0-9A-Za-z_]+\.png$/)
    );
  });
});

describe('the wing on the right', () => {
  const sizes = Object.fromEntries(
    ITEMS.map(({ sprite }) => [sprite, { width: 32, height: 32 }])
  );
  const grid = buildCollision(sizes);
  const corridor = FLOORS.find(area => area.room === 'CORRIDOR');
  // The middle of the floor of an area.
  const middle = room => {
    const floor = FLOORS.find(area => area.room === room);
    return { x: floor.x + floor.w / 2, y: floor.y + floor.h / 2 };
  };
  const reach = (walls, from, to) =>
    findPath(
      walls,
      nearestFree(walls, cellOf(from), 1),
      nearestFree(walls, cellOf(to), 1)
    );
  // The same clinic with the corridor (and the copa door to the garden)
  // closed off.
  const closed = grid.slice();
  const close = (left, top, width, height) => {
    for (let x = left; x < left + width; x += CELL) {
      for (let y = top; y < top + height; y += CELL) {
        const { column, row } = cellOf({ x, y });
        closed[row * COLUMNS + column] = 1;
      }
    }
  };
  close(corridor.x, corridor.y, corridor.w, corridor.h);
  close(
    BACK_DOOR.x - CELL,
    WORLD.height - CELL,
    BACK_DOOR.width + 2 * CELL,
    3 * CELL
  );

  it('reaches every room from the entrance', () => {
    ['MARKETING', 'MANAGEMENT', 'KITCHEN', 'CORRIDOR'].forEach(room =>
      expect(reach(grid, feetOf(ENTRANCE), middle(room)), room).not.toBeNull()
    );
  });

  it('only gets to the rooms through the corridor', () => {
    ['MARKETING', 'MANAGEMENT', 'KITCHEN'].forEach(room =>
      expect(reach(closed, feetOf(ENTRANCE), middle(room)), room).toBeNull()
    );
    // No more passage from the sala de espera to the copa.
    expect(reach(closed, middle('WAITING_ROOM'), middle('KITCHEN'))).toBeNull();
  });

  it('seats Luciano in the sala de marketing', () => {
    const marketing = FLOORS.find(area => area.room === 'MARKETING');
    const { x, y } = DEFAULT_LAYOUT.team.marketing;
    expect(x).toBeGreaterThanOrEqual(marketing.x);
    expect(x + 32).toBeLessThanOrEqual(marketing.x + marketing.w);
    expect(y + 64).toBeLessThanOrEqual(marketing.y + marketing.h);
  });
});

describe('hitTest', () => {
  it('finds the teammate under the pointer, wherever they are now', () => {
    const clara = { persona: 'secretary', x: 440, y: 140 };
    const helena = { persona: 'manager', ...CHARACTERS.manager };

    expect(hitTest(456, 180, [clara, helena])).toBe('secretary');
    expect(hitTest(456, 142, [clara, helena])).toBeUndefined();
    expect(
      hitTest(CHARACTERS.secretary.x + 16, CHARACTERS.secretary.y + 40, [clara])
    ).toBeUndefined();
  });
});
