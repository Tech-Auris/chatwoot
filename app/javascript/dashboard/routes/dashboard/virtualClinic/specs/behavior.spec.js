import { describe, it, expect } from 'vitest';
import { createTeamBehavior as createBehavior } from '../engine/behavior';
import { CHARACTERS, DEFAULT_LAYOUT, ITEMS } from '../engine/layout';
import { buildCollision } from '../engine/collision';
import { TRIPS, planTrip } from '../engine/trips';

const grid = buildCollision(
  Object.fromEntries(
    ITEMS.map(({ sprite }) => [sprite, { width: 32, height: 32 }])
  )
);
const plan = trip => planTrip(trip, { layout: DEFAULT_LAYOUT, grid });
const createTeamBehavior = options => createBehavior({ plan, ...options });

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

    run(behavior, 8600, 60000);
    expect([clara.x, clara.y]).toEqual([
      CHARACTERS.secretary.x,
      CHARACTERS.secretary.y,
    ]);
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
        expect([secretary.x, secretary.y]).toEqual([1028, 140]);
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

  it('sits Clara at the copa table, then brings her back to her desk', () => {
    const index = TRIPS.findIndex(trip => trip.key === 'clara_sits_copa');
    const behavior = createTeamBehavior({
      personas: ['secretary', 'manager'],
      random: () => (index + 0.5) / TRIPS.length,
    });
    const clara = behavior.state.secretary;
    let sat = false;
    for (let now = 0; now <= 120000 && !(sat && !clara.away); now += 100) {
      behavior.update(now);
      if (clara.sitting) {
        sat = true;
        expect(clara.direction).toBe('right');
      }
    }

    expect(sat).toBe(true);
    expect([clara.x, clara.y]).toEqual([
      CHARACTERS.secretary.x,
      CHARACTERS.secretary.y,
    ]);
    expect(clara.sitting).toBe(false);
  });

  it("walks Helena to Clara's desk while she asks her, and back after", () => {
    const behavior = createTeamBehavior({
      personas: ['secretary', 'manager'],
      random: () => 0,
    });
    const helena = behavior.state.manager;
    behavior.consult('manager', 'secretary', 0);
    run(behavior, 0, 60000);
    expect(helena).toMatchObject({
      away: true,
      talking: true,
      direction: 'up',
    });
    expect(behavior.state.secretary.talking).toBe(true);

    behavior.release(60000);
    run(behavior, 60100, 90000);
    expect([helena.x, helena.y]).toEqual([
      CHARACTERS.manager.x,
      CHARACTERS.manager.y,
    ]);
    expect(helena.away).toBe(false);
  });

  it('walks Luciano to Helena through the corridor, and Helena to him', () => {
    ['luciano_visits_helena', 'helena_visits_luciano'].forEach(key => {
      const trip = TRIPS.find(t => t.key === key);
      const path = plan(trip);
      expect(path, key).not.toBeNull();
      // Out of one room, along the corridor, into the other.
      expect(path.some(([, y]) => y + 60 > 256)).toBe(true);
    });
  });

  it('takes Luciano to the monitors, the campaigns board, Helena and the water, never to Clara', () => {
    const luciano = TRIPS.filter(trip => trip.who === 'marketing').map(
      trip => trip.key
    );
    expect(luciano.sort()).toEqual([
      'luciano_campaign_board',
      'luciano_monitors',
      'luciano_visits_helena',
      'luciano_water',
    ]);
    expect(
      TRIPS.filter(
        trip =>
          (trip.who === 'marketing' && trip.visit === 'secretary') ||
          (trip.who === 'secretary' && trip.visit === 'marketing')
      )
    ).toEqual([]);
  });

  it("walks Luciano to Helena's desk while he asks her, and back after", () => {
    const behavior = createTeamBehavior({
      personas: ['secretary', 'manager', 'marketing'],
      random: () => 0,
    });
    const luciano = behavior.state.marketing;
    behavior.consult('marketing', 'manager', 0);
    run(behavior, 0, 60000);
    expect(luciano).toMatchObject({ away: true, talking: true });
    expect(behavior.state.manager.talking).toBe(true);

    behavior.release(60000);
    run(behavior, 60100, 120000);
    expect([luciano.x, luciano.y]).toEqual([
      CHARACTERS.marketing.x,
      CHARACTERS.marketing.y,
    ]);
  });

  it('finds a way for every walk, from the teammate seat', () => {
    TRIPS.forEach(trip => {
      const path = plan(trip);
      const seat = CHARACTERS[trip.who];
      expect(path, trip.key).not.toBeNull();
      expect(path[0]).toEqual([seat.x, seat.y]);
    });
  });

  it('skips a walk to something that is no longer in the clinic', () => {
    const layout = { ...DEFAULT_LAYOUT, items: [] };
    const fridge = TRIPS.find(trip => trip.key === 'clara_fridge');
    expect(planTrip(fridge, { layout, grid })).toBeNull();
  });

  it('goes to the new seat of a teammate who was moved', () => {
    const layout = {
      ...DEFAULT_LAYOUT,
      team: {
        ...DEFAULT_LAYOUT.team,
        manager: { ...CHARACTERS.manager, x: 840, y: 150 },
      },
    };
    const visit = TRIPS.find(trip => trip.key === 'clara_visits_helena');
    expect(planTrip(visit, { layout, grid }).at(-1)).toEqual([840, 200]);
  });
});
