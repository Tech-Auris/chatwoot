import {
  DOOR,
  GARDEN_ITEMS,
  ITEMS,
  PARTITION,
  SCENE,
  WALLS,
  WORLD,
} from './layout';

// Where people can stand, on a grid of 16 px cells (half a tile, so the
// passages and the space between chairs stay open). Walls, the middle
// partition and the base of every piece of furniture block; people walk
// behind the top of a piece, like in Gather's 3/4 view.
export const CELL = 16;
// The grid covers the whole scene (clinic and garden); cell 0 is its corner.
export const COLUMNS = SCENE.width / CELL;
export const ROWS = SCENE.height / CELL;

// Characters are 32×64 frames; they stand on the point under their feet.
export const feetOf = ({ x, y }) => ({ x: x + 16, y: y + 60 });
export const frameAt = ({ x, y }) => ({ x: x - 16, y: y - 60 });

const WALL_HEIGHT = 64;
const FOOT_MIN = 16;
const FOOT_MAX = 32;

const fillRect = (grid, left, top, right, bottom, value) => {
  const firstColumn = Math.max(0, Math.floor((left - SCENE.x) / CELL));
  const lastColumn = Math.min(
    COLUMNS - 1,
    Math.ceil((right - SCENE.x) / CELL) - 1
  );
  const firstRow = Math.max(0, Math.floor((top - SCENE.y) / CELL));
  const lastRow = Math.min(ROWS - 1, Math.ceil((bottom - SCENE.y) / CELL) - 1);
  for (let row = firstRow; row <= lastRow; row += 1) {
    for (let column = firstColumn; column <= lastColumn; column += 1) {
      grid[row * COLUMNS + column] = value;
    }
  }
};
const blockRect = (grid, left, top, right, bottom) =>
  fillRect(grid, left, top, right, bottom, 1);

// The base of a piece: its bottom half, between 16 and 32 px high. Things
// standing on a desk (`sortY`) and wall decoration take no floor.
export function footprint(item, size) {
  if (item.sortY !== undefined) return null;
  const bottom = item.y + size.height;
  if (bottom <= WALL_HEIGHT) return null;
  const height = Math.min(FOOT_MAX, Math.max(FOOT_MIN, size.height / 2));
  return {
    left: item.x,
    top: Math.max(item.y, bottom - height, WALL_HEIGHT),
    right: item.x + size.width,
    bottom,
  };
}

// `sizes[sprite]` is `{ width, height }` of each piece as drawn (cropped).
export function buildCollision(sizes, items = ITEMS) {
  const grid = new Uint8Array(COLUMNS * ROWS);
  WALLS.forEach(wall =>
    blockRect(grid, wall.x, wall.y, wall.x + wall.w, wall.y + WALL_HEIGHT)
  );
  let top = 0;
  [...PARTITION.gaps, [WORLD.height, WORLD.height]].forEach(
    ([gapTop, gapBottom]) => {
      blockRect(grid, PARTITION.x, top, PARTITION.x + PARTITION.width, gapTop);
      top = gapBottom;
    }
  );
  items.forEach(item => {
    const base = sizes[item.sprite] && footprint(item, sizes[item.sprite]);
    if (base) blockRect(grid, base.left, base.top, base.right, base.bottom);
  });
  // The outer frame of the clinic, open at the glass door.
  blockRect(grid, 0, WORLD.height - 4, WORLD.width, WORLD.height);
  blockRect(grid, 0, 0, 4, WORLD.height);
  blockRect(grid, WORLD.width - 4, 0, WORLD.width, WORLD.height);
  fillRect(grid, DOOR.x, -CELL, DOOR.x + DOOR.width, WALL_HEIGHT, 0);
  // Garden trees and bushes block at their trunk / base only.
  GARDEN_ITEMS.forEach(item => {
    const size = sizes[item.sprite];
    if (!size) return;
    const middle = item.x + size.width / 2;
    const bottom = item.y + size.height;
    blockRect(grid, middle - 12, bottom - 16, middle + 12, bottom);
  });
  return grid;
}

export const cellOf = point => ({
  column: Math.floor((point.x - SCENE.x) / CELL),
  row: Math.floor((point.y - SCENE.y) / CELL),
});

export const centerOf = cell => ({
  x: SCENE.x + cell.column * CELL + CELL / 2,
  y: SCENE.y + cell.row * CELL + CELL / 2,
});

export function isFree(grid, point) {
  const { column, row } = cellOf(point);
  if (column < 0 || row < 0 || column >= COLUMNS || row >= ROWS) return false;
  return grid[row * COLUMNS + column] === 0;
}
