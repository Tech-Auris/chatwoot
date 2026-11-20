import { cellOf, centerOf, COLUMNS, feetOf, frameAt, ROWS } from './collision';
import { corners, findPath } from './pathfinding';

// Little walks of the AI team around the clinic, Gather-style. Each walk
// goes to a spot next to something on the map (a piece of furniture, a
// teammate's desk or a room), so it still works after the clinic is edited;
// the way there is found on the collision grid. Every walk starts at the
// teammate's seat and they always come back to it to work.
//
// At the end they `look` (stand facing `face`), `talk` with `talkWith`, or
// `sit` (on a chair, facing `face`). `offset` is from the top-left of the
// piece (or of the teammate's frame, or of the room label) to where the
// walker's frame stops.
const both = (key, target) => [
  { key: `clara_${key}`, who: 'secretary', ...target },
  { key: `helena_${key}`, who: 'manager', ...target },
];

export const TRIPS = [
  {
    key: 'clara_visits_helena',
    who: 'secretary',
    visit: 'manager',
    offset: [0, 50],
    face: 'up',
    talkWith: 'manager',
  },
  {
    key: 'helena_visits_clara',
    who: 'manager',
    visit: 'secretary',
    offset: [0, 75],
    face: 'up',
    talkWith: 'secretary',
  },
  ...both('waiting_room', {
    room: 'WAITING_ROOM',
    offset: [312, 102],
    face: 'down',
  }),
  ...both('water', {
    near: '4_copa/bebedouro.png',
    offset: [-4, 21],
    face: 'up',
  }),
  ...both('fridge', {
    near: '4_copa/geladeira.png',
    offset: [12, 20],
    face: 'up',
  }),
  {
    key: 'clara_sits_copa',
    who: 'secretary',
    near: '4_copa/cadeira_lado.png',
    flip: true,
    offset: [-6, -34],
    face: 'right',
    sit: true,
  },
  {
    key: 'helena_sits_copa',
    who: 'manager',
    near: '4_copa/cadeira_lado.png',
    flip: false,
    offset: [-4, -34],
    face: 'left',
    sit: true,
  },
  {
    key: 'clara_plant',
    who: 'secretary',
    near: '1_recepcao/planta_grande.png',
    offset: [6, 13],
    face: 'up',
  },
  {
    key: 'helena_plant',
    who: 'manager',
    near: '3_gerencia/planta.png',
    offset: [-16, 4],
    face: 'right',
  },
  {
    key: 'helena_charts',
    who: 'manager',
    near: '3_gerencia/quadro_graficos.png',
    offset: [14, 48],
    face: 'up',
  },
  {
    key: 'helena_diplomas',
    who: 'manager',
    near: '3_gerencia/diploma_2.png',
    offset: [0, 39],
    face: 'up',
  },
];

// Where the walker's frame stops, or null when the thing is not on the map.
export function tripTarget(trip, layout) {
  const [dx, dy] = trip.offset;
  if (trip.visit) {
    const seat = layout.team[trip.visit];
    return seat ? { x: seat.x + dx, y: seat.y + dy } : null;
  }
  if (trip.room) {
    const room = layout.rooms.find(({ key }) => key === trip.room);
    return room ? { x: room.x + dx, y: room.y + dy } : null;
  }
  const item = layout.items.find(
    ({ sprite, flip }) =>
      sprite === trip.near &&
      (trip.flip === undefined || Boolean(flip) === trip.flip)
  );
  return item ? { x: item.x + dx, y: item.y + dy } : null;
}

const STEPS = [
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];

// The free cell closest to `cell` (a chair or a plant takes the exact spot).
export function nearestFree(grid, cell, radius = 6) {
  const seen = new Set([`${cell.column},${cell.row}`]);
  let ring = [cell];
  for (let step = 0; step <= radius && ring.length; step += 1) {
    const found = ring.find(
      ({ column, row }) =>
        column >= 0 &&
        row >= 0 &&
        column < COLUMNS &&
        row < ROWS &&
        !grid[row * COLUMNS + column]
    );
    if (found) return found;
    const next = [];
    ring.forEach(({ column, row }) =>
      STEPS.forEach(([dc, dr]) => {
        const neighbour = { column: column + dc, row: row + dr };
        const key = `${neighbour.column},${neighbour.row}`;
        if (seen.has(key)) return;
        seen.add(key);
        next.push(neighbour);
      })
    );
    ring = next;
  }
  return null;
}

// The last step onto a chair (or right up to a plant) skips the grid, as
// long as it is short.
const LAST_STEP = 40;

// The frame positions of the walk, from the seat to the target, or null
// when there is no way there.
export function planTrip(trip, { layout, grid }) {
  const target = grid && tripTarget(trip, layout);
  const seat = layout.team[trip.who];
  if (!target || !seat) return null;
  const goal = nearestFree(grid, cellOf(feetOf(target)));
  const path = goal && findPath(grid, cellOf(feetOf(seat)), goal);
  if (!path) return null;
  const points = [
    { x: seat.x, y: seat.y },
    ...corners(path)
      .slice(1)
      .map(cell => frameAt(centerOf(cell))),
  ];
  const last = points.at(-1);
  if (Math.hypot(target.x - last.x, target.y - last.y) <= LAST_STEP) {
    points.push(target);
  }
  return points.map(({ x, y }) => [x, y]);
}
