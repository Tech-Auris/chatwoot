// The glass door of the recepção slides open when someone walks up to it
// and closes a moment after the last one went through. The art is the
// static door of the pack: its two leaves slide into the wall, the frame
// stays, and the garden shows through the opening.
export const GLASS_DOOR = '1_recepcao/porta_vidro_entrada.png';

// How long the door stays open after nobody is near, and how long each
// leaf takes to slide all the way.
export const HOLD_MS = 1500;
export const SLIDE_MS = 450;

// In the sprite as loaded (64×50, cropped to its outline): the opening
// inside the frame, where each leaf is and how far it slides (a sliver
// stays out of the wall).
const OPENING = { x: 3, y: 4, w: 58, h: 45 };
const LEAF = { left: 3, right: 32, width: 29 };
const SLIDE = 26;
const OUTSIDE = '#d9ecd2';
const SHADOW = '#b9d4b0';

// Someone's feet (bottom of their 32×64 frame) in front of the door, on
// either side of it.
export const nearDoor = (door, { x, y }) => {
  const feetX = x + 16;
  const feetY = y + 60;
  return (
    Math.abs(feetX - (door.x + 32)) <= 40 &&
    feetY >= door.y - 48 &&
    feetY <= door.y + OPENING.y + OPENING.h + 48
  );
};

// How open (0–1) a door is, frame after frame: `update(door, characters,
// now)` with `now` in ms.
export function createDoor() {
  let openness = 0;
  let lastNear = -Infinity;
  let last = null;
  return (door, characters, now) => {
    if (characters.some(character => nearDoor(door, character))) {
      lastNear = now;
    }
    const opening = now - lastNear < HOLD_MS;
    const step = last === null ? 0 : (now - last) / SLIDE_MS;
    last = now;
    openness = opening
      ? Math.min(1, openness + step)
      : Math.max(0, openness - step);
    return openness;
  };
}

// Eased slide in pixels: starts and ends softly.
export const slideOf = openness =>
  Math.round(SLIDE * openness * openness * (3 - 2 * openness));

// The opening of a door, in world pixels.
export const openingOf = door => ({
  x: door.x + OPENING.x,
  y: door.y + OPENING.y,
  w: OPENING.w,
  h: OPENING.h,
});

// The garden seen through the open door, drawn before the people so whoever
// goes through shows in front of it.
export function drawDoorway(context, door, openness) {
  if (!slideOf(openness)) return;
  const open = openingOf(door);
  context.fillStyle = OUTSIDE;
  context.fillRect(open.x, open.y, open.w, open.h);
  context.fillStyle = SHADOW;
  context.fillRect(open.x, open.y, open.w, 3);
}

// The leaves and the frame, over whoever is in the doorway.
export function drawGlassDoor(context, image, door, openness) {
  const slide = slideOf(openness);
  if (!slide) {
    context.drawImage(image, door.x, door.y);
    return;
  }
  const open = openingOf(door);
  // The leaves slide into the wall: nothing of them past the opening.
  context.save();
  context.beginPath();
  context.rect(open.x, open.y, open.w, open.h);
  context.clip();
  [
    [LEAF.left, -slide],
    [LEAF.right, slide],
  ].forEach(([sx, dx]) =>
    context.drawImage(
      image,
      sx,
      OPENING.y,
      LEAF.width,
      OPENING.h,
      door.x + sx + dx,
      open.y,
      LEAF.width,
      OPENING.h
    )
  );
  context.restore();
  // The frame around the opening, over the leaves.
  const { width, height } = image;
  const right = OPENING.x + OPENING.w;
  const bottom = OPENING.y + OPENING.h;
  [
    [0, 0, width, OPENING.y],
    [0, OPENING.y, OPENING.x, height - OPENING.y],
    [right, OPENING.y, width - right, height - OPENING.y],
    [0, bottom, width, height - bottom],
  ].forEach(([sx, sy, w, h]) =>
    context.drawImage(image, sx, sy, w, h, door.x + sx, door.y + sy, w, h)
  );
}
