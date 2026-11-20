import { COLUMNS, ROWS } from './collision';

const NEIGHBOURS = [
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];

// A* in 4 directions over the collision grid. Returns the cells from
// `start` to `goal` (both included), or null when there is no way there.
export function findPath(grid, start, goal) {
  const index = ({ column, row }) => row * COLUMNS + column;
  const inside = ({ column, row }) =>
    column >= 0 && row >= 0 && column < COLUMNS && row < ROWS;
  if (!inside(goal) || grid[index(goal)]) return null;
  const estimate = cell =>
    Math.abs(cell.column - goal.column) + Math.abs(cell.row - goal.row);

  const cost = new Map([[index(start), 0]]);
  const cameFrom = new Map();
  const open = [{ cell: start, score: estimate(start) }];
  const closed = new Set();

  while (open.length) {
    let best = 0;
    for (let i = 1; i < open.length; i += 1) {
      if (open[i].score < open[best].score) best = i;
    }
    const { cell } = open.splice(best, 1)[0];
    const key = index(cell);
    if (key === index(goal)) {
      const path = [cell];
      let step = key;
      while (cameFrom.has(step)) {
        const previous = cameFrom.get(step);
        path.unshift(previous.cell);
        step = previous.key;
      }
      return path;
    }
    if (!closed.has(key)) {
      closed.add(key);
      NEIGHBOURS.forEach(([dc, dr]) => {
        const next = { column: cell.column + dc, row: cell.row + dr };
        const nextKey = index(next);
        if (!inside(next) || grid[nextKey] || closed.has(nextKey)) return;
        const nextCost = cost.get(key) + 1;
        if (nextCost >= (cost.get(nextKey) ?? Infinity)) return;
        cost.set(nextKey, nextCost);
        cameFrom.set(nextKey, { cell, key });
        open.push({ cell: next, score: nextCost + estimate(next) });
      });
    }
  }
  return null;
}

// Keeps only the corners of a path, so walking along it looks straight.
export function corners(path) {
  if (path.length <= 2) return path;
  return path.filter((cell, i) => {
    if (i === 0 || i === path.length - 1) return true;
    const before = path[i - 1];
    const after = path[i + 1];
    return (
      cell.column - before.column !== after.column - cell.column ||
      cell.row - before.row !== after.row - cell.row
    );
  });
}
