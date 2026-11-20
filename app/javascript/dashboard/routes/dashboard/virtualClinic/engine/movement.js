// The user's own avatar: walks with the arrows / WASD, or along a path
// (click on the floor). `canStand(position)` says whether a frame position
// (top-left of the 32×64 sprite) is free; with the keyboard the avatar
// slides along walls and furniture instead of stopping dead.
const SPEED = 128; // world px per second

const KEYS = {
  arrowup: [0, -1],
  w: [0, -1],
  arrowdown: [0, 1],
  s: [0, 1],
  arrowleft: [-1, 0],
  a: [-1, 0],
  arrowright: [1, 0],
  d: [1, 0],
};

export const isMovementKey = key => key.toLowerCase() in KEYS;

const facing = (dx, dy) => {
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? 'right' : 'left';
  return dy >= 0 ? 'down' : 'up';
};

export function createAvatar({ x, y, canStand }) {
  const state = { x, y, direction: 'down', moving: false };
  const pressed = new Set();
  let path = [];

  const stepKeyboard = seconds => {
    let dx = 0;
    let dy = 0;
    pressed.forEach(key => {
      dx += KEYS[key][0];
      dy += KEYS[key][1];
    });
    if (!dx && !dy) return false;
    const length = Math.hypot(dx, dy);
    const distance = SPEED * seconds;
    const [startX, startY] = [state.x, state.y];
    const nextX = state.x + (dx / length) * distance;
    const nextY = state.y + (dy / length) * distance;
    if (canStand({ x: nextX, y: state.y })) state.x = nextX;
    if (canStand({ x: state.x, y: nextY })) state.y = nextY;
    state.direction = facing(dx, dy);
    return state.x !== startX || state.y !== startY;
  };

  const stepPath = seconds => {
    let budget = SPEED * seconds;
    while (budget > 0 && path.length) {
      const [target] = path;
      const dx = target.x - state.x;
      const dy = target.y - state.y;
      const distance = Math.hypot(dx, dy);
      if (distance) state.direction = facing(dx, dy);
      if (distance <= budget) {
        state.x = target.x;
        state.y = target.y;
        budget -= distance;
        path.shift();
      } else {
        state.x += (dx / distance) * budget;
        state.y += (dy / distance) * budget;
        budget = 0;
      }
    }
    return true;
  };

  return {
    state,
    // True when the key moves the avatar (the page should not scroll).
    press(key) {
      const name = key.toLowerCase();
      if (!(name in KEYS)) return false;
      pressed.add(name);
      path = [];
      return true;
    },
    release(key) {
      pressed.delete(key.toLowerCase());
    },
    releaseAll() {
      pressed.clear();
    },
    walkTo(points) {
      path = [...points];
    },
    update(seconds) {
      if (pressed.size) state.moving = stepKeyboard(seconds);
      else if (path.length) state.moving = stepPath(seconds);
      else state.moving = false;
    },
  };
}
