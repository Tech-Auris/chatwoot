import {
  BACK_DOOR,
  DEFAULT_LAYOUT,
  FACADE,
  PLAZA,
  GARDEN_ITEMS,
  PARTITION,
  SCENE,
  TILE,
  WORLD,
  sheetOf,
} from './layout';

const FRAME = { width: 32, height: 64 };
const OUTLINE = '#2b2d42';
// The garden ground around the clinic (Gather-like light grass).
const GRASS = '#d9ecd2';
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

// `scale` draws a garden piece bigger or smaller; `flip` mirrors it.
function drawItem(context, image, item) {
  const width = Math.round(image.width * (item.scale || 1));
  const height = Math.round(image.height * (item.scale || 1));
  if (!item.flip) {
    context.drawImage(image, item.x, item.y, width, height);
    return;
  }
  context.save();
  context.translate(item.x + width, item.y);
  context.scale(-1, 1);
  context.drawImage(image, 0, 0, width, height);
  context.restore();
}

// The outside wall under the clinic, as seen from the garden: gray, with a
// row of windows (Gather-style).
const WALL_OUTSIDE = {
  wall: '#a3adb3',
  edge: '#868f95',
  trim: '#eef1f4',
  frame: '#4a5677',
  glass: '#8fd3f4',
  door: '#efdcc4',
  brick: '#e3cba9',
};
const WINDOW = { width: 72, height: 40, every: 160, top: 14 };
function drawFacade(context) {
  const top = WORLD.height;
  context.fillStyle = WALL_OUTSIDE.wall;
  context.fillRect(0, top, WORLD.width, FACADE);
  context.fillStyle = WALL_OUTSIDE.trim;
  context.fillRect(0, top, WORLD.width, 4);
  context.fillStyle = WALL_OUTSIDE.edge;
  context.fillRect(0, top + FACADE - 4, WORLD.width, 4);
  for (let x = 44; x + WINDOW.width < WORLD.width; x += WINDOW.every) {
    const y = top + WINDOW.top;
    context.fillStyle = WALL_OUTSIDE.frame;
    context.fillRect(x, y, WINDOW.width, WINDOW.height);
    context.fillStyle = WALL_OUTSIDE.glass;
    context.fillRect(x + 3, y + 3, WINDOW.width - 6, WINDOW.height - 6);
    context.fillStyle = WALL_OUTSIDE.frame;
    context.fillRect(x + 3, y + WINDOW.height / 2 - 1, WINDOW.width - 6, 3);
    [1, 2].forEach(part =>
      context.fillRect(
        x + (WINDOW.width * part) / 3 - 1,
        y + 3,
        3,
        WINDOW.height - 6
      )
    );
  }
  // The copa door: an opening in the wall, light bricks inside.
  context.fillStyle = WALL_OUTSIDE.door;
  context.fillRect(BACK_DOOR.x, top - 4, BACK_DOOR.width, FACADE + 4);
  context.fillStyle = WALL_OUTSIDE.brick;
  for (let y = top + 6; y < top + FACADE; y += 12) {
    context.fillRect(BACK_DOOR.x, y, BACK_DOOR.width, 2);
  }
}

// The garden square: a lighter lawn with a border.
const SQUARE = { lawn: '#cfe5c7', border: '#b7d8ad' };
function drawPlaza(context) {
  context.fillStyle = SQUARE.lawn;
  context.fillRect(PLAZA.x, PLAZA.y, PLAZA.w, PLAZA.h);
  context.strokeStyle = SQUARE.border;
  context.lineWidth = 4;
  context.strokeRect(PLAZA.x + 2, PLAZA.y + 2, PLAZA.w - 4, PLAZA.h - 4);
}

// The zoomed-out view, Gather-style: the clinic as a plan (rooms in soft
// colors, furniture as plain blocks, trees as round tops), no characters.
const PLAN = {
  rooms: ['#f4f5fb', '#eef3fb', '#f8f1e8', '#f1f1f1'],
  wall: '#dcdff3',
  furniture: '#e4e6ec',
  tree: '#a9d4a0',
};
function drawPlan(context, layout, items) {
  layout.floors.forEach((floor, index) => {
    context.fillStyle = PLAN.rooms[index % PLAN.rooms.length];
    context.fillRect(floor.x, floor.y, floor.w, floor.h);
  });
  context.fillStyle = PLAN.wall;
  layout.walls.forEach(wall =>
    context.fillRect(wall.x, wall.y, wall.w, 2 * TILE)
  );
  items.forEach(item => {
    const width = item.image.width * (item.scale || 1);
    const height = item.image.height * (item.scale || 1);
    if (/(arvore|cipreste|pinheiro)/.test(item.sprite)) {
      context.fillStyle = PLAN.tree;
      context.beginPath();
      context.arc(
        item.x + width / 2,
        item.y + height / 3,
        width / 2.6,
        0,
        2 * Math.PI
      );
      context.fill();
      return;
    }
    if (item.y + height <= 2 * TILE) return;
    context.fillStyle = PLAN.furniture;
    context.fillRect(
      item.x + 2,
      item.y + height / 2,
      width - 4,
      height / 2 - 2
    );
  });
  context.fillStyle = PLAN.wall;
  context.fillRect(0, WORLD.height, WORLD.width, FACADE);
  context.strokeStyle = PLAN.wall;
  context.lineWidth = 6;
  context.strokeRect(0, 0, WORLD.width, WORLD.height);
  context.fillStyle = PLAN.wall;
  context.fillRect(PARTITION.x, 0, PARTITION.width, WORLD.height);
}

// Draws the clinic and its garden into `canvas` (scene size). `characters` lists the AI
// teammates (`persona`) and the people walking around (`sheet`): `{ x, y,
// direction, moving, phone, talking, faded }`, `x`/`y` being the top-left
// of their 32×64 frame.
export function createRenderer(canvas, sprites, layout = DEFAULT_LAYOUT) {
  const context = canvas.getContext('2d');
  context.imageSmoothingEnabled = false;
  const background = drawBackground(sprites, layout);
  const items = [...GARDEN_ITEMS, ...layout.items]
    .filter(item => sprites[item.sprite])
    .map(item => ({
      ...item,
      image: sprites[item.sprite],
      depth:
        item.sortY ?? item.y + sprites[item.sprite].height * (item.scale || 1),
    }));

  // `selected` (editor): the box of the piece or teammate being moved;
  // `plan`: the zoomed-out view.
  return function draw(characters, tick, selected = null, plan = false) {
    // World coordinates from here on (the garden is at negative ones).
    context.setTransform(1, 0, 0, 1, -SCENE.x, -SCENE.y);
    context.fillStyle = GRASS;
    context.fillRect(SCENE.x, SCENE.y, SCENE.width, SCENE.height);
    drawPlaza(context);
    if (plan) {
      drawPlan(context, layout, items);
      return;
    }
    context.drawImage(background, 0, 0);
    drawFacade(context);
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
