import { describe, it, expect } from 'vitest';
import { createTeamBehavior } from '../engine/behavior';
import { CHARACTERS } from '../engine/layout';
import { TRIPS } from '../engine/trips';

// `random` always 0: first trip after the minimum wait, first trip option.
const run = (behavior, from, to, step = 100) => {
  for (let now = from; now <= to; now += step) behavior.update(now);
};

describe('team behavior', () => {
  it('walks Clara to Helena, they talk, and she comes back to her seat', () => {
    const behavior = createTeamBehavior({
      personas: ['secretary', 'manager'],
      random: () => 0,
    });
    const clara = behavior.state.secretary;

    run(behavior, 0, 7900);
    expect(clara.away).toBe(false);

    run(behavior, 8000, 8500);
    expect(clara).toMatchObject({ away: true, moving: true });

    const destination = TRIPS[0].path.at(-1);
    run(behavior, 8600, 30000);
    expect([clara.x, clara.y]).toEqual([
      CHARACTERS.secretary.x,
      CHARACTERS.secretary.y,
    ]);
    expect(destination).toEqual([708, 140]);
    expect(clara).toMatchObject({
      away: false,
      moving: false,
      talking: false,
      direction: 'down',
    });
  });

  it("makes both talk while Clara stands at Helena's desk", () => {
    const behavior = createTeamBehavior({
      personas: ['secretary', 'manager'],
      random: () => 0,
    });
    let talked = false;
    for (let now = 0; now <= 30000; now += 100) {
      behavior.update(now);
      const { secretary, manager } = behavior.state;
      if (secretary.talking && manager.talking) {
        talked = true;
        expect(secretary.direction).toBe('up');
        expect([secretary.x, secretary.y]).toEqual([708, 140]);
      }
    }
    expect(talked).toBe(true);
  });

  it('keeps someone at their seat while the user is talking to them', () => {
    const behavior = createTeamBehavior({
      personas: ['secretary', 'manager'],
      canLeave: persona => persona !== 'secretary',
      random: () => 0,
    });
    run(behavior, 0, 20000);

    expect(behavior.state.secretary.away).toBe(false);
    expect(behavior.state.manager.away).toBe(true);
  });

  it('only takes walks that start at the teammate seat', () => {
    TRIPS.forEach(trip => {
      const seat = CHARACTERS[trip.who];
      expect(trip.path[0]).toEqual([seat.x, seat.y]);
    });
  });
});
