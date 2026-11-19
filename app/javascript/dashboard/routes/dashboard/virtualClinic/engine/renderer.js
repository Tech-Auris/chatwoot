import {
  CHARACTERS,
  FLOORS,
  ITEMS,
  PARTITION,
  TILE,
  WALLS,
  WORLD,
} from './layout';

const FRAME = { width: 32, height: 64 };
// Rows and columns of the LimeZu character sheet, facing the viewer.
export const ANIMATIONS = {
  idle: { row: 1, columns: [18, 19, 20, 21, 22, 23] },
  phone: { row: 6, columns: [3, 4, 5, 6, 7, 8] },
};
const OUTLINE = '#2b2d42';

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

function drawBackground(sprites) {
  const canvas = document.createElement('canvas');
  canvas.width = WORLD.width;
  canvas.height = WORLD.height;
  const context = canvas.getContext('2d');
  context.imageSmoothingEnabled = false;
  FLOORS.forEach(floor => repeatBlock(context, sprites[floor.block], floor));
  WALLS.forEach(wall => drawWall(context, sprites[wall.block], wall));
  context.fillStyle = OUTLINE;
  let top = 0;
  [...PARTITION.gaps, [WORLD.height, WORLD.height]].forEach(
    ([gapTop, gapBottom]) => {
      context.fillRect(PARTITION.x, top, PARTITION.width, gapTop - top);
      top = gapBottom;
    }
  );
  context.fillRect(PARTITION.x, WALLS[2].y - 4, WORLD.width - PARTITION.x, 4);
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
// teammates to show: `{ persona, animation, faded }`.
export function createRenderer(canvas, sprites) {
  const context = canvas.getContext('2d');
  context.imageSmoothingEnabled = false;
  const background = drawBackground(sprites);
  const items = ITEMS.map(item => ({
    ...item,
    image: sprites[item.sprite],
    depth: item.sortY ?? item.y + sprites[item.sprite].height,
  }));

  return function draw(characters, tick) {
    context.clearRect(0, 0, WORLD.width, WORLD.height);
    context.drawImage(background, 0, 0);
    const people = characters.map(character => ({
      ...character,
      spot: CHARACTERS[character.persona],
      depth: CHARACTERS[character.persona].y + FRAME.height,
    }));
    // Stable sort: on a tie the furniture (a chair behind someone) goes first.
    [...items, ...people]
      .sort((a, b) => a.depth - b.depth)
      .forEach(entry => {
        if (!entry.spot) {
          drawItem(context, entry.image, entry);
          return;
        }
        const { row, columns } = ANIMATIONS[entry.animation];
        const column = columns[tick % columns.length];
        context.globalAlpha = entry.faded ? 0.45 : 1;
        context.drawImage(
          sprites[entry.spot.sheet],
          column * FRAME.width,
          row * FRAME.height,
          FRAME.width,
          FRAME.height,
          entry.spot.x,
          entry.spot.y,
          FRAME.width,
          FRAME.height
        );
        context.globalAlpha = 1;
      });
  };
}

// The AI teammate under a world point, if any (the visible body of the frame).
export function hitTest(x, y, personas) {
  return personas.find(persona => {
    const spot = CHARACTERS[persona];
    return (
      x >= spot.x &&
      x < spot.x + FRAME.width &&
      y >= spot.y + 16 &&
      y < spot.y + FRAME.height
    );
  });
}
