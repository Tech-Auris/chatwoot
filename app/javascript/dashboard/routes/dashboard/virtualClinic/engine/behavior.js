import { CHARACTERS } from './layout';
import { TRIPS } from './trips';

const SPEED = 64; // world px per second
const STAY_MS = 5000;
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
// talking to them).
export function createTeamBehavior({
  personas,
  canLeave = () => true,
  random = Math.random,
}) {
  const home = persona => [CHARACTERS[persona].x, CHARACTERS[persona].y];
  const state = Object.fromEntries(
    personas.map(persona => {
      const [x, y] = home(persona);
      return [
        persona,
        { x, y, direction: 'down', moving: false, talking: false, away: false },
      ];
    })
  );
  let trip = null;
  let nextTripAt = null;

  const startTrip = now => {
    const options = TRIPS.filter(
      t =>
        personas.includes(t.who) &&
        canLeave(t.who) &&
        (!t.talkWith || personas.includes(t.talkWith))
    );
    if (!options.length) return;
    const chosen = options[Math.floor(random() * options.length)];
    trip = {
      ...chosen,
      points: chosen.path,
      index: 1,
      phase: 'going',
      stayUntil: 0,
    };
    state[trip.who].away = true;
    state[trip.who].moving = true;
    state[trip.who].startedAt = now;
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
      });
      if (trip.talkWith) state[trip.talkWith].talking = true;
      trip.phase = 'staying';
      trip.stayUntil = now + STAY_MS;
    } else {
      finishTrip(now);
    }
  };

  let last = null;
  return {
    state,
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
