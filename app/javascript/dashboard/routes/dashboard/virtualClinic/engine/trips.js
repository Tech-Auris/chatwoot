// Little walks of the AI team around the clinic, Gather-style. Paths are
// frame positions (top-left of the 32×64 sprite) that go around the
// furniture and through the two passages of the middle wall; there is no
// door between the gerência and the copa, so the copa is reached through
// the sala de espera. Every path starts at the teammate's desk and they
// always come back to it to work.
//
// At the end of the path they `look` (stand facing `face`), `talk` with
// `talkWith`, or `sit` (on a copa chair, facing `face`).
const CLARA_OUT = [
  [304, 87],
  [304, 58],
  [440, 58],
  [440, 140],
];
const HELENA_OUT = [
  [708, 90],
  [644, 90],
  [644, 140],
];
// Helena going around her desk, along the wall of her room.
const HELENA_WALL = [
  [708, 90],
  [708, 56],
];
// From the recepção down the sala de espera and into the copa.
const TO_COPA = [
  [560, 140],
  [560, 448],
  [660, 448],
];
const TO_WAITING_ROOM = [
  [560, 140],
  [560, 430],
  [320, 430],
];
const COPA_LEFT_CHAIR = [
  [660, 481],
  [742, 481],
  [742, 458],
];
const COPA_RIGHT_CHAIR = [
  [660, 481],
  [824, 481],
  [824, 458],
];

const forBoth = (key, steps, extra) => [
  {
    key: `clara_${key}`,
    who: 'secretary',
    path: [...CLARA_OUT, ...steps],
    ...extra,
  },
  {
    key: `helena_${key}`,
    who: 'manager',
    path: [...HELENA_OUT, ...steps],
    ...extra,
  },
];

export const TRIPS = [
  {
    key: 'clara_visits_helena',
    who: 'secretary',
    path: [...CLARA_OUT, [708, 140]],
    face: 'up',
    talkWith: 'manager',
  },
  {
    key: 'helena_visits_clara',
    who: 'manager',
    path: [...HELENA_OUT, [460, 140], [460, 162], [304, 162]],
    face: 'up',
    talkWith: 'secretary',
  },
  ...forBoth('waiting_room', TO_WAITING_ROOM, { face: 'down' }),
  ...forBoth('water', [...TO_COPA, [660, 376], [866, 376]], { face: 'up' }),
  ...forBoth('fridge', [...TO_COPA, [660, 352]], { face: 'up' }),
  {
    key: 'clara_sits_copa',
    who: 'secretary',
    path: [...CLARA_OUT, ...TO_COPA, ...COPA_LEFT_CHAIR],
    face: 'right',
    sit: true,
  },
  {
    key: 'helena_sits_copa',
    who: 'manager',
    path: [...HELENA_OUT, ...TO_COPA, ...COPA_RIGHT_CHAIR],
    face: 'left',
    sit: true,
  },
  {
    key: 'clara_plant',
    who: 'secretary',
    path: [
      [304, 87],
      [304, 58],
      [566, 58],
    ],
    face: 'up',
  },
  {
    key: 'helena_plant',
    who: 'manager',
    path: [...HELENA_WALL, [904, 56]],
    face: 'right',
  },
  {
    key: 'helena_charts',
    who: 'manager',
    path: [...HELENA_WALL, [666, 56]],
    face: 'up',
  },
  {
    key: 'helena_diplomas',
    who: 'manager',
    path: [...HELENA_WALL, [760, 56]],
    face: 'up',
  },
];
