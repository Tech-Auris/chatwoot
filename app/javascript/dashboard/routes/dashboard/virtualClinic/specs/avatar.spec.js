import { describe, it, expect } from 'vitest';
import { ENTRANCE, ITEMS, sheetForUser } from '../engine/layout';
import {
  COLUMNS,
  ROWS,
  buildCollision,
  cellOf,
  centerOf,
  feetOf,
  footprint,
  isFree,
} from '../engine/collision';
import { corners, findPath } from '../engine/pathfinding';
import { createAvatar } from '../engine/movement';

// Every piece 32×32, which is about what the pack crops to.
const sizes = Object.fromEntries(
  ITEMS.map(({ sprite }) => [sprite, { width: 32, height: 32 }])
);
const grid = buildCollision(sizes);
const emptyGrid = () => new Uint8Array(COLUMNS * ROWS);
const block = (target, column, row) => {
  target[row * COLUMNS + column] = 1;
};

describe('collision', () => {
  it('blocks the walls and the middle partition but keeps both passages open', () => {
    expect(isFree(grid, { x: 300, y: 40 })).toBe(false);
    expect(isFree(grid, { x: 640, y: 120 })).toBe(false);
    expect(isFree(grid, { x: 640, y: 224 })).toBe(true);
    expect(isFree(grid, { x: 640, y: 512 })).toBe(true);
  });

  it('blocks the base of the furniture, not its top', () => {
    const plant = { sprite: 'x.png', x: 100, y: 200 };
    expect(footprint(plant, { width: 32, height: 64 })).toEqual({
      left: 100,
      top: 232,
      right: 132,
      bottom: 264,
    });
    const items = [plant];
    const withPlant = buildCollision(
      { 'x.png': { width: 32, height: 64 } },
      items
    );
    expect(isFree(withPlant, { x: 110, y: 250 })).toBe(false);
    expect(isFree(withPlant, { x: 110, y: 210 })).toBe(true);
  });

  it('ignores things on a desk and on the wall', () => {
    expect(
      footprint({ x: 0, y: 150, sortY: 197 }, { width: 20, height: 20 })
    ).toBeNull();
    expect(footprint({ x: 0, y: 10 }, { width: 20, height: 40 })).toBeNull();
  });

  it('lets people arrive at the entrance', () => {
    expect(isFree(grid, feetOf(ENTRANCE))).toBe(true);
  });
});

describe('findPath', () => {
  it('goes around an obstacle', () => {
    const walls = emptyGrid();
    [0, 1, 2, 3].forEach(row => block(walls, 5, row));
    const path = findPath(walls, { column: 3, row: 1 }, { column: 7, row: 1 });
    expect(path[0]).toEqual({ column: 3, row: 1 });
    expect(path.at(-1)).toEqual({ column: 7, row: 1 });
    expect(path.some(cell => cell.column === 5 && cell.row <= 3)).toBe(false);
    expect(path.length).toBe(11);
  });

  it('returns null when there is no way there', () => {
    const walls = emptyGrid();
    [0, 1, 2].forEach(row => block(walls, 5, row));
    [5, 6, 7].forEach(column => block(walls, column, 2));
    [0, 1, 2].forEach(row => block(walls, 7, row));
    expect(
      findPath(walls, { column: 1, row: 1 }, { column: 6, row: 1 })
    ).toBeNull();
  });

  it('returns null for a blocked destination', () => {
    const walls = emptyGrid();
    block(walls, 2, 2);
    expect(
      findPath(walls, { column: 0, row: 0 }, { column: 2, row: 2 })
    ).toBeNull();
  });

  it('crosses from the recepção to the copa through the sala de espera', () => {
    const path = findPath(
      grid,
      cellOf(feetOf(ENTRANCE)),
      cellOf({ x: 800, y: 600 })
    );
    expect(path).not.toBeNull();
    path.forEach(cell => expect(isFree(grid, centerOf(cell))).toBe(true));
  });

  it('goes out to the garden through the glass door only', () => {
    const outside = { x: -80, y: -80 };
    const path = findPath(grid, cellOf(feetOf(ENTRANCE)), cellOf(outside));
    expect(path).not.toBeNull();
    // Leaves the clinic at the door, in the top wall.
    const exit = path.find(cell => centerOf(cell).y < 0);
    expect(centerOf(exit).x).toBeGreaterThanOrEqual(48);
    expect(centerOf(exit).x).toBeLessThanOrEqual(96);
    // No way through the side walls.
    expect(isFree(grid, { x: 2, y: 300 })).toBe(false);
    expect(isFree(grid, { x: -40, y: 300 })).toBe(true);
  });

  it('keeps only the turns of a path', () => {
    const path = [
      { column: 0, row: 0 },
      { column: 1, row: 0 },
      { column: 2, row: 0 },
      { column: 2, row: 1 },
      { column: 2, row: 2 },
    ];
    expect(corners(path)).toEqual([
      { column: 0, row: 0 },
      { column: 2, row: 0 },
      { column: 2, row: 2 },
    ]);
  });
});

describe('createAvatar', () => {
  const free = () => true;

  it('walks with the arrows and WASD, facing where it goes', () => {
    const avatar = createAvatar({ x: 100, y: 100, canStand: free });
    expect(avatar.press('ArrowRight')).toBe(true);
    avatar.update(0.5);
    expect(avatar.state).toMatchObject({
      x: 164,
      y: 100,
      direction: 'right',
      moving: true,
    });
    avatar.release('ArrowRight');
    avatar.press('W');
    avatar.update(0.25);
    expect(avatar.state).toMatchObject({ x: 164, y: 68, direction: 'up' });
    avatar.release('w');
    avatar.update(0.1);
    expect(avatar.state.moving).toBe(false);
  });

  it('ignores other keys', () => {
    const avatar = createAvatar({ x: 0, y: 0, canStand: free });
    expect(avatar.press('Enter')).toBe(false);
  });

  it('does not walk into furniture and slides along it', () => {
    const avatar = createAvatar({
      x: 100,
      y: 100,
      canStand: place => place.x <= 110,
    });
    avatar.press('d');
    avatar.press('s');
    avatar.update(0.5);
    expect(avatar.state.x).toBe(100);
    expect(avatar.state.y).toBeGreaterThan(140);
  });

  it('follows a path to the end', () => {
    const avatar = createAvatar({ x: 0, y: 0, canStand: free });
    avatar.walkTo([
      { x: 64, y: 0 },
      { x: 64, y: 64 },
    ]);
    avatar.update(0.75);
    expect(avatar.state).toMatchObject({ x: 64, y: 32, direction: 'down' });
    avatar.update(1);
    expect(avatar.state).toMatchObject({ x: 64, y: 64 });
    avatar.update(0.1);
    expect(avatar.state.moving).toBe(false);
  });
});

describe('sheetForUser', () => {
  it('always gives the same person the same character', () => {
    expect(sheetForUser(7)).toBe(sheetForUser(7));
    expect(sheetForUser(7)).toMatch(/^8_pessoas\/pessoa_\d{2}\.png$/);
  });
});
