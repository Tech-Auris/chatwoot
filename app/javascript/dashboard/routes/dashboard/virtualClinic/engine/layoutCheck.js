import { ENTRANCE } from './layout';
import { buildCollision, cellOf, feetOf, isFree } from './collision';
import { findPath } from './pathfinding';
import { nearestFree } from './trips';

// What the editor checks before saving a clinic: people must be able to get
// in, and to walk from the entrance up to every AI teammate (who may sit on
// a chair, so a free spot right next to the seat is enough). Returns
// `{ problem: 'entrance' }`, `{ problem: 'unreachable', persona }` or null.
export function checkLayout(layout, sizes) {
  const grid = buildCollision(sizes, layout.items);
  const entrance = feetOf(ENTRANCE);
  if (!isFree(grid, entrance)) return { problem: 'entrance' };
  const start = cellOf(entrance);
  const blocked = Object.entries(layout.team).find(([, seat]) => {
    const spot = nearestFree(grid, cellOf(feetOf(seat)), 2);
    return !spot || !findPath(grid, start, spot);
  });
  return blocked ? { problem: 'unreachable', persona: blocked[0] } : null;
}
