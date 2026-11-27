import { describe, it, expect } from 'vitest';
import {
  HOLD_MS,
  SLIDE_MS,
  createDoor,
  nearDoor,
  slideOf,
} from '../engine/door';

const DOOR = { x: 40, y: 14 };
// A character frame whose feet stand at (feetX, feetY).
const at = (feetX, feetY) => ({ x: feetX - 16, y: feetY - 60 });

describe('recepção glass door', () => {
  it('knows who is in front of it, inside or outside', () => {
    expect(nearDoor(DOOR, at(72, 100))).toBe(true);
    expect(nearDoor(DOOR, at(72, -20))).toBe(true);
    expect(nearDoor(DOOR, at(72, 200))).toBe(false);
    expect(nearDoor(DOOR, at(200, 100))).toBe(false);
  });

  it('slides open while someone is near', () => {
    const update = createDoor();
    const near = [at(72, 100)];
    expect(update(DOOR, near, 0)).toBe(0);
    expect(update(DOOR, near, SLIDE_MS / 2)).toBeCloseTo(0.5);
    expect(update(DOOR, near, SLIDE_MS)).toBe(1);
    expect(update(DOOR, near, SLIDE_MS * 3)).toBe(1);
  });

  it('stays open for a moment after they pass, then closes', () => {
    const update = createDoor();
    update(DOOR, [at(72, 100)], 0);
    update(DOOR, [at(72, 100)], SLIDE_MS);
    const away = [at(300, 300)];
    const passed = SLIDE_MS + HOLD_MS;
    expect(update(DOOR, away, passed - 1)).toBe(1);
    expect(update(DOOR, away, passed + SLIDE_MS / 2)).toBeCloseTo(0.5, 1);
    expect(update(DOOR, away, passed + SLIDE_MS * 2)).toBe(0);
  });

  it('stays closed with nobody around', () => {
    const update = createDoor();
    update(DOOR, [], 0);
    expect(update(DOOR, [at(300, 300)], 5000)).toBe(0);
  });

  it('eases the slide, closed to all the way into the wall', () => {
    expect(slideOf(0)).toBe(0);
    expect(slideOf(0.5)).toBe(13);
    expect(slideOf(1)).toBe(26);
  });
});
