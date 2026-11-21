import { DEFAULT_LAYOUT, PARTITION, TILE, WORLD, sheetOf } from './layout';

const FRAME = { width: 32, height: 64 };
const OUTLINE = '#2b2d42';
// Rows of the LimeZu character sheet: 6 frames per direction, in the order
// right, up (back), left, down (front). The phone call only faces front.
const DIRECTIONS = ['right', 'up', 'left', 'down'];
const ROWS = { idle: 1, walk: 2, sit: 4, sitCompact: 5 };
const PHONE = { row: 6, columns: [3, 4, 5, 6, 7, 8] };

function frameOf(character, tick) {
  if (character.phone) {
    return { row: PHONE.row, column: PHONE.columns[Math.floor(tick / 2) % 6] };
  }
  const base = DIRECTIONS.indexOf(character.direction || 'down') * 6;
  if (character.moving) return { row: ROWS.walk, column: base + (tick % 6) };
  if (character.sitting && ['left', 'right'].includes(character.direction)) {
    // Seated frames only face right (0–5) or left (6–11); armchairs and
    // sofas use the compact ones. Facing up or down, the standing frames
    // go on the seat.
    const side = character.direction === 'left' ? 6 : 0;
    const row = character.compact ? ROWS.sitCompact : ROWS.sit;
    return { row, column: side + (Math.floor(tick / 3) % 6) };
  }
  return { row: ROWS.idle, column: base + (Math.floor(tick / 2) % 6) };
}

const sittingDepth = ({ sitting, direction }) => {
  if (!sitting) return 0;
  return direction === 'left' || direction === 'right' ? 40 : 8;
};

// The Gather-like "talking" balloon: three dots, no words, to the right of
// the mouth with its tail pointing at it.
function drawTalking(context, x, y, tick) {
  const left = x + 29;
  const top = y + 24;
  context.fillStyle = '#ffffff';
  context.strokeStyle = OUTLINE;
  context.lineWidth = 1;
  context.beginPath();
  context.roundRect(left, top, 24, 12, 4);
  context.fill();
  context.stroke();
  context.beginPath();
  context.moveTo(left + 1, top + 6);
  context.lineTo(left - 4, top + 11);
  context.lineTo(left + 1, top + 10);
  context.fill();
  context.stroke();
  context.fillRect(left + 1, top + 6, 2, 4);
  [0, 1, 2].forEach(dot => {
    context.fillStyle = Math.floor(tick / 3) % 3 === dot ? OUTLINE : '#9ca3af';
    context.fillRect(left + 5 + dot * 6, top + 5, 3, 3);
  });
}

function repeatBlock(context, block, area) {
  for (let y = area.y; y < area.y + area.h; y += block.height) {
    for (let x = area.x; x < area.x + area.w; x += block.width) {
      const w = Math.min(block.width, area.x + area.w - x);
      const h = Math.min(block.height, area.y + area.h - y);
      context.drawImage(block, 0, 0, w, h, x, y, w, h);
    }
  }
}

// A wall is two tiles high: left column, middle column repeated, right column.
function drawWall(context, block, wall) {
  const height = 2 * TILE;
  context.drawImage(block, 0, 0, TILE, height, wall.x, wall.y, TILE, height);
  for (let x = wall.x + TILE; x < wall.x + wall.w - TILE; x += TILE) {
    context.drawImage(block, TILE, 0, TILE, height, x, wall.y, TILE, height);
  }
  context.drawImage(
    block,
    2 * TILE,
    0,
    TILE,
    height,
    wall.x + wall.w - TILE,
    wall.y,
    TILE,
    height
  );
}

function drawBackground(sprites, layout) {
  const canvas = document.createElement('canvas');
  canvas.width = WORLD.width;
  canvas.height = WORLD.height;
  const context = canvas.getContext('2d');
  context.imageSmoothingEnabled = false;
  layout.floors.forEach(floor =>
    repeatBlock(context, sprites[floor.block], floor)
  );
  layout.walls.forEach(wall => drawWall(context, sprites[wall.block], wall));
  context.fillStyle = OUTLINE;
  let top = 0;
  [...PARTITION.gaps, [WORLD.height, WORLD.height]].forEach(
    ([gapTop, gapBottom]) => {
      context.fillRect(PARTITION.x, top, PARTITION.width, gapTop - top);
      top = gapBottom;
    }
  );
  context.fillRect(
    PARTITION.x,
    layout.walls[2].y - 4,
    WORLD.width - PARTITION.x,
    4
  );
  context.lineWidth = 4;
  context.strokeRect(2, 2, WORLD.width - 4, WORLD.height - 4);
  return canvas;
}

function drawItem(context, image, item) {
  if (!item.flip) {
    context.drawImage(image, item.x, item.y);
    return;
  }
  context.save();
  context.translate(item.x + image.width, item.y);
  context.scale(-1, 1);
  context.drawImage(image, 0, 0);
  context.restore();
}

// Draws the clinic into `canvas` (world size). `characters` lists the AI
// teammates (`persona`) and the people walking around (`sheet`): `{ x, y,
// direction, moving, phone, talking, faded }`, `x`/`y` being the top-left
// of their 32×64 frame.
export function createRenderer(canvas, sprites, layout = DEFAULT_LAYOUT) {
  const context = canvas.getContext('2d');
  context.imageSmoothingEnabled = false;
  const background = drawBackground(sprites, layout);
  const items = layout.items.map(item => ({
    ...item,
    image: sprites[item.sprite],
    depth: item.sortY ?? item.y + sprites[item.sprite].height,
  }));

  // `selected` (editor): the box of the piece or teammate being moved.
  return function draw(characters, tick, selected = null) {
    context.clearRect(0, 0, WORLD.width, WORLD.height);
    context.drawImage(background, 0, 0);
    const people = characters
      .map(character => ({
        ...character,
        sheet:
          sprites[character.sheet || sheetOf(layout.team[character.persona])],
        // Someone sitting goes over their chair; sideways, over the whole
        // sofa (the upper place of a side sofa too).
        depth: character.y + FRAME.height + sittingDepth(character),
      }))
      .filter(person => person.sheet);
    // Stable sort: on a tie the furniture (a chair behind someone) goes first.
    [...items, ...people]
      .sort((a, b) => a.depth - b.depth)
      .forEach(entry => {
        if (!entry.sheet) {
          drawItem(context, entry.image, entry);
          return;
        }
        const { row, column } = frameOf(entry, tick);
        context.globalAlpha = entry.faded ? 0.45 : 1;
        context.drawImage(
          entry.sheet,
          column * FRAME.width,
          row * FRAME.height,
          FRAME.width,
          FRAME.height,
          Math.round(entry.x),
          Math.round(entry.y),
          FRAME.width,
          FRAME.height
        );
        context.globalAlpha = 1;
      });
    people
      .filter(person => person.talking)
      .forEach(person =>
        drawTalking(context, Math.round(person.x), Math.round(person.y), tick)
      );
    if (selected) {
      context.save();
      context.strokeStyle = '#2563eb';
      context.lineWidth = 2;
      context.setLineDash([4, 3]);
      context.strokeRect(
        Math.round(selected.x) - 2,
        Math.round(selected.y) - 2,
        selected.width + 4,
        selected.height + 4
      );
      context.restore();
    }
  };
}

// Index of the piece of furniture under a world point (the one drawn in
// front wins), or -1.
export function itemAt(x, y, items, sprites) {
  let found = -1;
  let frontmost = -Infinity;
  items.forEach((item, i) => {
    const image = sprites[item.sprite];
    if (!image) return;
    const inside =
      x >= item.x &&
      x < item.x + image.width &&
      y >= item.y &&
      y < item.y + image.height;
    const depth = item.sortY ?? item.y + image.height;
    if (inside && depth > frontmost) {
      found = i;
      frontmost = depth;
    }
  });
  return found;
}

// The AI teammate under a world point, if any (the visible body of the
// frame). `characters` are `{ persona, x, y }` where they are now.
export function hitTest(x, y, characters) {
  return characters.find(
    c =>
      c.persona &&
      x >= c.x &&
      x < c.x + FRAME.width &&
      y >= c.y + 16 &&
      y < c.y + FRAME.height
  )?.persona;
}
