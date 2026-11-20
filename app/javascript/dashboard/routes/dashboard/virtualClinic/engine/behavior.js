import { DEFAULT_LAYOUT } from './layout';
import { TRIPS } from './trips';

const SPEED = 64; // world px per second
const STAY_MS = [3500, 8000];
const FIRST_TRIP_MS = [8000, 15000];
const NEXT_TRIP_MS = [25000, 55000];

const between = ([min, max], random) => min + random() * (max - min);

function directionTo(from, to) {
  const dx = to[0] - from[0];
  const dy = to[1] - from[1];
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? 'right' : 'left';
  return dy >= 0 ? 'down' : 'up';
}

// Runs one walk at a time for the AI team: go along the path, stay a few
// seconds (talking, when it is a visit) and come back the same way.
// `canLeave(persona)` keeps someone at their seat (e.g. while the user is
// talking to them). `plan(trip)` gives the frame positions of the walk
// (see planTrip), or null to skip it.
export function createTeamBehavior({
  personas,
  plan,
  layout = DEFAULT_LAYOUT,
  canLeave = () => true,
  random = Math.random,
}) {
  const home = persona => [layout.team[persona].x, layout.team[persona].y];
  const state = Object.fromEntries(
    personas.map(persona => {
      const [x, y] = home(persona);
      return [
        persona,
        {
          x,
          y,
          direction: 'down',
          moving: false,
          talking: false,
          sitting: false,
          away: false,
        },
      ];
    })
  );
  let trip = null;
  let nextTripAt = null;
  let lastTripKey = null;

  const startTrip = now => {
    // Random walk, never the same one twice in a row.
    const options = TRIPS.filter(
      t =>
        t.key !== lastTripKey &&
        personas.includes(t.who) &&
        canLeave(t.who) &&
        (!t.talkWith || personas.includes(t.talkWith))
    );
    if (!options.length) return;
    const chosen = options[Math.floor(random() * options.length)];
    lastTripKey = chosen.key;
    const path = plan(chosen);
    if (!path) {
      nextTripAt = now + between(NEXT_TRIP_MS, random);
      return;
    }
    trip = {
      ...chosen,
      path,
      points: path,
      index: 1,
      phase: 'going',
      stayUntil: 0,
    };
    state[trip.who].away = true;
    state[trip.who].moving = true;
  };

  const finishTrip = now => {
    const walker = state[trip.who];
    Object.assign(walker, {
      moving: false,
      talking: false,
      away: false,
      direction: 'down',
    });
    if (trip.talkWith) state[trip.talkWith].talking = false;
    trip = null;
    nextTripAt = now + between(NEXT_TRIP_MS, random);
  };

  const walk = (walker, seconds, now) => {
    let budget = SPEED * seconds;
    while (budget > 0 && trip.index < trip.points.length) {
      const target = trip.points[trip.index];
      const dx = target[0] - walker.x;
      const dy = target[1] - walker.y;
      const distance = Math.hypot(dx, dy);
      walker.direction = directionTo([walker.x, walker.y], target);
      if (distance <= budget) {
        [walker.x, walker.y] = target;
        budget -= distance;
        trip.index += 1;
      } else {
        walker.x += (dx / distance) * budget;
        walker.y += (dy / distance) * budget;
        budget = 0;
      }
    }
    if (trip.index < trip.points.length) return;
    if (trip.phase === 'going') {
      Object.assign(walker, {
        moving: false,
        direction: trip.face,
        talking: Boolean(trip.talkWith),
        sitting: Boolean(trip.sit),
      });
      if (trip.talkWith) state[trip.talkWith].talking = true;
      trip.phase = 'staying';
      trip.stayUntil = trip.held ? Infinity : now + between(STAY_MS, random);
    } else {
      finishTrip(now);
    }
  };

  // Back home at once, dropping the walk in progress.
  const cancelTrip = now => {
    if (!trip) return;
    const [x, y] = home(trip.who);
    Object.assign(state[trip.who], { x, y, sitting: false });
    finishTrip(now);
  };

  let last = null;
  return {
    state,
    // `who` goes to `target`'s desk and stays there talking until release()
    // (the manager asking the secretary something).
    consult(who, target, now) {
      const chosen = TRIPS.find(t => t.who === who && t.visit === target);
      if (!chosen || !personas.includes(who) || !personas.includes(target)) {
        return;
      }
      cancelTrip(now);
      const path = plan(chosen);
      if (!path) return;
      trip = {
        ...chosen,
        path,
        points: path,
        index: 1,
        phase: 'going',
        stayUntil: 0,
        held: true,
      };
      state[who].away = true;
      state[who].moving = true;
    },
    release(now) {
      if (!trip?.held) return;
      trip.held = false;
      if (trip.phase === 'staying') trip.stayUntil = now;
    },
    update(now) {
      const seconds = last === null ? 0 : Math.min(0.25, (now - last) / 1000);
      last = now;
      if (nextTripAt === null)
        nextTripAt = now + between(FIRST_TRIP_MS, random);
      if (!trip) {
        if (now >= nextTripAt) startTrip(now);
        return;
      }
      const walker = state[trip.who];
      if (trip.phase === 'staying') {
        if (now < trip.stayUntil) return;
        walker.talking = false;
        walker.sitting = false;
        if (trip.talkWith) state[trip.talkWith].talking = false;
        trip.points = [...trip.path].reverse();
        trip.index = 1;
        trip.phase = 'returning';
        walker.moving = true;
        return;
      }
      walk(walker, seconds, now);
    },
  };
}
