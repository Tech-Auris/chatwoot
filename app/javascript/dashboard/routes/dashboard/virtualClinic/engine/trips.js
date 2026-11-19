// Little walks of the AI team around the clinic, Gather-style. Paths are
// frame positions (top-left of the 32×64 sprite) that go around the
// furniture and through the two passages of the middle wall; there is no
// door between the gerência and the copa, so the copa is reached through
// the sala de espera. The first point of every path is the teammate's seat.
const CLARA_OUT = [
  [304, 87],
  [304, 58],
  [440, 58],
  [440, 140],
];
const HELENA_OUT = [
  [708, 70],
  [644, 70],
  [644, 140],
];
// From the recepção, down the sala de espera and into the copa.
const TO_COPA = [
  [560, 140],
  [560, 448],
  [660, 448],
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
  {
    key: 'clara_water',
    who: 'secretary',
    path: [...CLARA_OUT, ...TO_COPA, [660, 376], [866, 376]],
    face: 'up',
  },
  {
    key: 'helena_water',
    who: 'manager',
    path: [...HELENA_OUT, ...TO_COPA, [660, 376], [866, 376]],
    face: 'up',
  },
  {
    key: 'clara_copa_table',
    who: 'secretary',
    path: [...CLARA_OUT, ...TO_COPA, [660, 481], [783, 481]],
    face: 'up',
  },
  {
    key: 'helena_copa_table',
    who: 'manager',
    path: [...HELENA_OUT, ...TO_COPA, [660, 481], [783, 481]],
    face: 'up',
  },
];
