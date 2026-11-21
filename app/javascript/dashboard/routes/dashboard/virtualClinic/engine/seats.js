import { feetOf } from './collision';

// Chairs, armchairs and sofas people sit on, Gather-style: walk onto one and
// the avatar sits down. A seat is known by its art: side chairs ("lado",
// "lateral") face where they point (the mirrored ones to the right), chairs
// seen from behind ("costas") have the sitter facing up, and the rest face
// the room. Double armchairs and sofas take two people. The AI team's desk
// chairs are left out: those are their seats.
const SEAT = /(cadeira|poltrona|sofa)/;
const SIDE = /(lado|lateral)/;
const BACK = /costas/;
const DOUBLE = /(dupla|sofa)/;
// Armchairs and sofas use the compact sitting frames (hands on the lap).
const SOFT = /(poltrona|sofa)/;
const TEAM_DISTANCE = 32;

const faceOf = (name, item) => {
  if (SIDE.test(name)) return item.flip ? 'right' : 'left';
  return BACK.test(name) ? 'up' : 'down';
};

// Where the sitter's 32×64 frame goes on a place of the seat: on the cushion,
// over the seat (or behind its back, facing up), tuned on the pack art.
const frameOn = (place, face) => {
  const x = Math.round(place.x + place.w / 2 - 16);
  if (face === 'up') return { x, y: Math.round(place.y - 50) };
  if (face === 'down') return { x, y: Math.round(place.y + place.h - 68) };
  return {
    x: x + (face === 'right' ? -1 : 1),
    y: Math.round(place.y + place.h - 66),
  };
};

// `sizes[sprite]` is the drawn size of each piece; `team` the AI seats.
export function seatsOf(items, sizes, team = {}) {
  const teamSpots = Object.values(team);
  return items.flatMap(item => {
    const name = item.sprite.split('/').pop();
    const size = sizes[item.sprite];
    if (!SEAT.test(name) || !size || item.sortY !== undefined) return [];
    const face = faceOf(name, item);
    const count = DOUBLE.test(name) ? 2 : 1;
    // A side sofa seats people one behind the other; the rest side by side.
    const stacked = face === 'left' || face === 'right';
    return Array.from({ length: count }, (_, index) => {
      const place = stacked
        ? {
            x: item.x,
            y: item.y + (index * size.height) / count,
            w: size.width,
            h: size.height / count,
          }
        : {
            x: item.x + (index * size.width) / count,
            y: item.y,
            w: size.width / count,
            h: size.height,
          };
      return {
        ...place,
        item,
        face,
        compact: SOFT.test(name),
        frame: frameOn(place, face),
      };
    }).filter(
      seat =>
        !teamSpots.some(
          spot =>
            Math.hypot(spot.x - seat.frame.x, spot.y - seat.frame.y) <
            TEAM_DISTANCE
        )
    );
  });
}

// The seat under the feet of a frame position, if any.
export function seatAt(seats, position) {
  const { x, y } = feetOf(position);
  return (
    seats.find(
      seat =>
        x >= seat.x - 2 &&
        x <= seat.x + seat.w + 2 &&
        y >= seat.y - 4 &&
        y <= seat.y + seat.h + 6
    ) || null
  );
}

// The pieces without the seats, so the avatar can step onto a chair.
export const withoutSeats = (items, seats) =>
  items.filter(item => !seats.some(seat => seat.item === item));
