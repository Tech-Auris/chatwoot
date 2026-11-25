import { lookSheet } from './avatar';

// The Clínica virtual (MVP: the same clinic for every account), from the
// approved draft: a 40×20 grid of 32 px tiles. Coordinates are world
// pixels; item positions are the top-left of the sprite cropped to its
// outline. Art comes from the LimeZu pack, served by the API (never in git).
export const TILE = 32;
export const WORLD = { width: 40 * TILE, height: 20 * TILE };

// Around the clinic, a garden people can walk in, Gather-style: the scene
// is the clinic plus a margin of grass. Clinic coordinates stay as they
// are (the garden is at negative coordinates and beyond the clinic size);
// the glass door of the recepção is the way in and out.
export const GARDEN = 8 * TILE;
// Below the clinic there's room for the garden square (koi pond, benches).
const GARDEN_BOTTOM = 16 * TILE;
export const SCENE = {
  x: -GARDEN,
  y: -GARDEN,
  width: WORLD.width + 2 * GARDEN,
  height: WORLD.height + GARDEN + GARDEN_BOTTOM,
};
export const DOOR = { x: 48, width: 48 };
// The outside wall under the clinic (seen from the garden, with windows),
// with a door from the copa to the garden.
export const FACADE = 2 * TILE;
export const BACK_DOOR = { x: 776, width: 48 };
// The garden square, centered under the clinic.
export const PLAZA = { x: 484, y: 752, w: 312, h: 240 };

const R = '1_recepcao/';
const E = '2_sala_de_espera/';
const G = '3_gerencia/';
const C = '4_copa/';
const M = '14_marketing/';

// The clinic wing (recepção + sala de espera) takes 20 columns. The other
// 20 hold the sala de marketing and the gerência side by side (10 columns
// each), the corridor under them and the copa under the corridor. Every
// door of that wing opens to the corridor.
const WING = 640;
const SIDE = 960;
const ROOMS_BOTTOM = 256;
const CORRIDOR_BOTTOM = 320;

// Floors repeat a 3×2-tile block; walls are 2 tiles high and repeat the
// middle column of their 3×2 block. The order is the one clinics saved
// (the areas added later come last); `room` names the area in the editor.
export const FLOORS = [
  {
    block: '5_pisos/porcelanato_branco_recepcao.png',
    x: 0,
    y: 64,
    w: WING,
    h: 256,
    room: 'RECEPTION',
  },
  {
    block: '5_pisos/piso_azul_claro_espera.png',
    x: 0,
    y: 320,
    w: WING,
    h: 320,
    room: 'WAITING_ROOM',
  },
  {
    block: '5_pisos/madeira_gerencia.png',
    x: SIDE,
    y: 64,
    w: 320,
    h: ROOMS_BOTTOM - 64,
    room: 'MANAGEMENT',
  },
  {
    block: '5_pisos/xadrez_cinza_copa.png',
    x: WING,
    y: 384,
    w: 640,
    h: 256,
    room: 'KITCHEN',
  },
  {
    block: '5_pisos/carpete_cinza.png',
    x: WING,
    y: 64,
    w: 320,
    h: ROOMS_BOTTOM - 64,
    room: 'MARKETING',
  },
  {
    block: '5_pisos/alternativa_branco_liso.png',
    x: WING,
    y: ROOMS_BOTTOM,
    w: 640,
    h: CORRIDOR_BOTTOM - ROOMS_BOTTOM,
    room: 'CORRIDOR',
  },
];

export const WALLS = [
  {
    block: '6_paredes/azul_com_cruz_recepcao_espera.png',
    x: 0,
    y: 0,
    w: WING,
    area: 'RECEPTION_WAITING',
  },
  {
    block: '6_paredes/bege_gerencia.png',
    x: SIDE,
    y: 0,
    w: 320,
    area: 'MANAGEMENT',
  },
  {
    block: '6_paredes/azulejo_branco_copa.png',
    x: WING,
    y: CORRIDOR_BOTTOM,
    w: 640,
    area: 'KITCHEN',
  },
  {
    block: '6_paredes/alternativa_branca.png',
    x: WING,
    y: 0,
    w: 320,
    area: 'MARKETING',
  },
];

// The thin walls inside the clinic, each with its doorways (`gaps`, along
// the wall): the recepção ↔ corridor door, the wall between the sala de
// marketing and the gerência, and the wall of both rooms to the corridor
// with their doors.
export const PARTITIONS = [
  { x: WING - 4, y: 0, w: 8, h: WORLD.height, gaps: [[256, 320]] },
  { x: SIDE - 4, y: 0, w: 8, h: ROOMS_BOTTOM, gaps: [] },
  {
    x: WING,
    y: ROOMS_BOTTOM - 4,
    w: 640,
    h: 8,
    gaps: [
      [864, 928],
      [1152, 1216],
    ],
  },
];

// The copa door: an opening in its tiled wall, to the corridor.
export const KITCHEN_DOOR = { x: 928, y: CORRIDOR_BOTTOM, w: 64, h: 64 };

// The solid parts of the thin walls, as rectangles.
export const partitionRects = () =>
  PARTITIONS.flatMap(wall => {
    const vertical = wall.h > wall.w;
    const start = vertical ? wall.y : wall.x;
    const end = start + (vertical ? wall.h : wall.w);
    const rects = [];
    let from = start;
    [...wall.gaps, [end, end]].forEach(([gapStart, gapEnd]) => {
      if (gapStart > from) {
        rects.push(
          vertical
            ? { x: wall.x, y: from, w: wall.w, h: gapStart - from }
            : { x: from, y: wall.y, w: gapStart - from, h: wall.h }
        );
      }
      from = gapEnd;
    });
    return rects;
  });

const chairsRow = xs =>
  xs.map(x => ({ sprite: `${E}cadeira_azul_costas.png`, x, y: 530 }));

// `sortY` overrides the depth (bottom edge) for things standing on a desk;
// `flip` mirrors the sprite.
export const ITEMS = [
  // Recepção
  { sprite: `${R}porta_vidro_entrada.png`, x: 40, y: 14 },
  { sprite: `${R}relogio.png`, x: 290, y: 15 },
  { sprite: `${R}quadro_cruz.png`, x: 388, y: 15 },
  { sprite: `${R}quadro_avisos.png`, x: 450, y: 15 },
  { sprite: `${R}flores_gaveteiro.png`, x: 175, y: 45 },
  { sprite: `${R}planta_grande.png`, x: 560, y: 45 },
  { sprite: `${R}cadeira_secretaria.png`, x: 304, y: 104 },
  { sprite: `${R}balcao_recepcao.png`, x: 224, y: 117 },
  { sprite: `${R}lixeira.png`, x: 432, y: 168 },
  { sprite: `${R}planta_media.png`, x: 12, y: 237 },
  { sprite: `${R}planta_media.png`, x: 596, y: 200 },
  // Sala de espera: the rows centered in the room, evenly spaced.
  { sprite: `${E}poltronas_beges_dupla.png`, x: 85, y: 352 },
  { sprite: `${E}mesinha_revistas.png`, x: 193, y: 367 },
  { sprite: `${E}poltronas_verdes_dupla.png`, x: 292, y: 352 },
  { sprite: `${E}mesinha_revistas_2.png`, x: 400, y: 367 },
  { sprite: `${E}poltronas_beges_dupla.png`, x: 494, y: 352 },
  { sprite: `${E}bebedouro.png`, x: 600, y: 427 },
  ...chairsRow([58, 91, 124, 157, 190, 223]),
  ...chairsRow([390, 423, 456, 489, 522, 555]),
  { sprite: `${E}flores_gaveteiro.png`, x: 305, y: 555 },
  { sprite: `${E}planta.png`, x: 8, y: 580 },
  { sprite: `${E}planta.png`, x: 596, y: 580 },
  // Sala de marketing: the wall of monitors and the campaigns board.
  { sprite: `${M}painel_monitores.png`, x: 668, y: 8 },
  { sprite: `${M}quadro_campanhas.png`, x: 792, y: 8 },
  { sprite: `${M}quadro_criativos.png`, x: 868, y: 12 },
  { sprite: `${M}planta.png`, x: 916, y: 52 },
  { sprite: `${M}cadeira_executiva.png`, x: 760, y: 108 },
  { sprite: `${M}mesa.png`, x: 744, y: 158 },
  // Two monitors seen from behind, facing Luciano.
  { sprite: `${M}monitor_costas.png`, x: 758, y: 150, sortY: 197 },
  { sprite: `${M}monitor_costas.png`, x: 787, y: 150, sortY: 197 },
  { sprite: `${M}poltrona_lateral.png`, x: 652, y: 186, flip: true },
  { sprite: `${M}planta_2.png`, x: 930, y: 196 },
  // Gerência
  { sprite: `${G}quadro_graficos.png`, x: 972, y: 8 },
  { sprite: `${G}diploma.png`, x: 1048, y: 17 },
  { sprite: `${G}diploma_2.png`, x: 1080, y: 17 },
  { sprite: `${G}diploma_3.png`, x: 1112, y: 17 },
  { sprite: `${G}arquivo.png`, x: 1168, y: 35 },
  { sprite: `${G}arquivo_2.png`, x: 1202, y: 35 },
  { sprite: `${G}planta.png`, x: 1240, y: 52 },
  { sprite: `${G}cadeira_executiva_frente.png`, x: 1028, y: 108 },
  { sprite: `${G}mesa_reta.png`, x: 996, y: 158 },
  { sprite: `${G}mesa_em_l.png`, x: 1060, y: 132 },
  // Two monitors seen from behind, facing Helena.
  { sprite: `${G}monitor_costas.png`, x: 1010, y: 150, sortY: 197 },
  { sprite: `${G}monitor_costas.png`, x: 1039, y: 150, sortY: 197 },
  { sprite: `${G}luminaria.png`, x: 1092, y: 116, sortY: 197 },
  { sprite: `${G}planta_2.png`, x: 968, y: 196 },
  { sprite: `${G}sofa_lateral.png`, x: 1248, y: 172 },
  // Copa
  { sprite: `${C}geladeira.png`, x: 648, y: 332 },
  { sprite: `${C}maquina_bebidas.png`, x: 706, y: 340 },
  { sprite: `${C}cafeteira_bancada.png`, x: 760, y: 360 },
  { sprite: `${C}maquina_cafe.png`, x: 816, y: 340 },
  { sprite: `${C}bebedouro.png`, x: 870, y: 355 },
  { sprite: `${C}cadeira_frente.png`, x: 788, y: 437 },
  { sprite: `${C}mesa_redonda.png`, x: 772, y: 470 },
  // Side chairs face the table: the left one is mirrored.
  { sprite: `${C}cadeira_lado.png`, x: 748, y: 492, flip: true },
  { sprite: `${C}cadeira_lado.png`, x: 828, y: 492 },
  { sprite: `${C}planta.png`, x: 648, y: 590 },
  { sprite: `${C}lixeira.png`, x: 920, y: 592 },
  // The other half of the copa, past its door.
  { sprite: `${C}maquina_lanches.png`, x: 1010, y: 340 },
  { sprite: `${C}cafeteira.png`, x: 1072, y: 352 },
  { sprite: `${C}cadeira_frente.png`, x: 1108, y: 437 },
  { sprite: `${C}mesa_redonda.png`, x: 1092, y: 470 },
  { sprite: `${C}cadeira_lado.png`, x: 1068, y: 492, flip: true },
  { sprite: `${C}cadeira_lado.png`, x: 1148, y: 492 },
  { sprite: `${C}planta.png`, x: 1240, y: 590 },
];

// The garden around the clinic (fixed, not part of the editor). `scale`
// draws the same tree bigger or smaller.
const J = '10_jardim/';
export const GARDEN_ITEMS = [
  // Above the clinic, leaving the way to the door free.
  { sprite: `${J}arvore_carvalho.png`, x: -230, y: -240 },
  { sprite: `${J}canteiro_flores_3.png`, x: -40, y: -44 },
  { sprite: `${J}canteiro_flores_1.png`, x: 128, y: -44 },
  { sprite: `${J}pinheiro.png`, x: 150, y: -220, scale: 1.3 },
  { sprite: `${J}arvore_redonda.png`, x: 240, y: -150, scale: 0.8 },
  { sprite: `${J}arvore_frondosa.png`, x: 330, y: -230 },
  { sprite: `${J}cipreste.png`, x: 500, y: -160, scale: 1.2 },
  { sprite: `${J}arvore_grande.png`, x: 600, y: -200 },
  { sprite: `${J}arbusto_pequeno.png`, x: 580, y: -46 },
  { sprite: `${J}arvore_larga.png`, x: 720, y: -120 },
  { sprite: `${J}pinheiro.png`, x: 900, y: -230, scale: 0.8 },
  { sprite: `${J}arvore_carvalho.png`, x: 1320, y: -200, scale: 0.8 },
  { sprite: `${J}arvore_redonda_2.png`, x: 1430, y: -110 },
  { sprite: `${J}arvore_frondosa.png`, x: 1100, y: -210, scale: 0.9 },
  { sprite: `${J}cipreste.png`, x: 1220, y: -150 },
  { sprite: `${J}arbusto_pequeno.png`, x: 1180, y: -46 },
  // Left.
  { sprite: `${J}arvore_grande_2.png`, x: -200, y: 0, scale: 1.3 },
  { sprite: `${J}pinheiro.png`, x: -90, y: 140, scale: 0.75 },
  { sprite: `${J}arvore_frondosa.png`, x: -250, y: 230, scale: 0.8 },
  { sprite: `${J}arbusto.png`, x: -60, y: 300 },
  { sprite: `${J}cipreste.png`, x: -150, y: 400 },
  { sprite: `${J}arvore_carvalho.png`, x: -240, y: 500, scale: 1.2 },
  { sprite: `${J}arvore_redonda.png`, x: -80, y: 640, scale: 0.7 },
  // Right.
  { sprite: `${J}arvore_copa.png`, x: 1320, y: 30, scale: 1.3 },
  { sprite: `${J}arvore_frondosa.png`, x: 1390, y: 150, scale: 0.8 },
  { sprite: `${J}cipreste_2.png`, x: 1310, y: 280, scale: 0.8 },
  { sprite: `${J}arvore_carvalho.png`, x: 1370, y: 330 },
  { sprite: `${J}pinheiro.png`, x: 1310, y: 470, scale: 1.2 },
  { sprite: `${J}arvore_grande.png`, x: 1430, y: 570, scale: 0.8 },
  { sprite: `${J}arbusto_pequeno.png`, x: 1300, y: 640 },
  // By the copa door, along the outside wall.
  { sprite: `${J}arbusto_pequeno.png`, x: 704, y: 708 },
  { sprite: `${J}arbusto_pequeno.png`, x: 736, y: 712 },
  { sprite: `${J}arbusto_pequeno.png`, x: 832, y: 712 },
  { sprite: `${J}arbusto_pequeno.png`, x: 864, y: 708 },
  // The garden square: the koi pond, benches and lounge chairs around it.
  { sprite: `${J}lago_carpas_anim16.png`, x: 581, y: 832, flat: true },
  { sprite: `${J}banco_frente.png`, x: 598, y: 764 },
  { sprite: `${J}espreguicadeira.png`, x: 524, y: 758 },
  { sprite: `${J}espreguicadeira.png`, x: 709, y: 758 },
  { sprite: `${J}banco_lado.png`, x: 500, y: 826, flip: true },
  { sprite: `${J}banco_lado.png`, x: 748, y: 826 },
  { sprite: `${J}banco_sem_encosto.png`, x: 542, y: 950 },
  { sprite: `${J}banco_sem_encosto.png`, x: 674, y: 950 },
  { sprite: `${J}capim.png`, x: 492, y: 764 },
  { sprite: `${J}capim.png`, x: 760, y: 764 },
  { sprite: `${J}arbusto_pequeno.png`, x: 494, y: 958 },
  { sprite: `${J}arbusto_pequeno.png`, x: 754, y: 958 },
  // Below, around the square.
  { sprite: `${J}arvore_grande_2.png`, x: -200, y: 720, scale: 0.9 },
  { sprite: `${J}arvore_redonda_2.png`, x: 60, y: 760 },
  { sprite: `${J}arvore_carvalho.png`, x: -40, y: 880 },
  { sprite: `${J}cipreste.png`, x: 200, y: 900, scale: 0.8 },
  { sprite: `${J}pinheiro.png`, x: -220, y: 1000, scale: 1.3 },
  { sprite: `${J}arvore_frondosa.png`, x: 150, y: 1040, scale: 0.8 },
  { sprite: `${J}arvore_redonda.png`, x: 1250, y: 760, scale: 0.8 },
  { sprite: `${J}arvore_grande.png`, x: 1020, y: 820, scale: 1.2 },
  { sprite: `${J}arvore_larga.png`, x: 1200, y: 900 },
  { sprite: `${J}cipreste_2.png`, x: 1440, y: 860, scale: 1.2 },
  { sprite: `${J}arvore_carvalho.png`, x: 1080, y: 990, scale: 0.8 },
  { sprite: `${J}arvore_copa.png`, x: 1410, y: 1040 },
  { sprite: `${J}canteiro_flores_5.png`, x: 596, y: 1040 },
  { sprite: `${J}pinheiro.png`, x: 490, y: 1050, scale: 0.75 },
  { sprite: `${J}arbusto.png`, x: 760, y: 1060 },
];

// Where each AI teammate sits (top-left of the 32×64 frame) and their
// spritesheet. Name and status are drawn over the head, wherever they are.
// A clinic can give them a look of its own in the avatar editor (`avatar`,
// which then wins over `sheet`). `seated`: how many px lower they are drawn
// while at their spot, so the desk in front hides their legs and they sit in
// the chair behind it.
export const CHARACTERS = {
  secretary: {
    sheet: '7_personagens/clara_secretaria_spritesheet.png',
    x: 304,
    y: 87,
    seated: 12,
  },
  manager: {
    sheet: '7_personagens/helena_opcao_A_spritesheet.png',
    x: 1028,
    y: 90,
  },
  marketing: {
    sheet: '7_personagens/luciano_marketing_spritesheet.png',
    x: 760,
    y: 90,
  },
};

// Where people arrive: in front of the glass door of the recepção.
export const ENTRANCE = { x: 52, y: 44 };

// The clinic team walks around as LimeZu premade characters, one per user.
export const PEOPLE_SHEETS = Array.from(
  { length: 18 },
  (_, i) => `8_pessoas/pessoa_${String(i + 1).padStart(2, '0')}.png`
);
export const sheetForUser = id => PEOPLE_SHEETS[id % PEOPLE_SHEETS.length];

// The premade characters the avatar editor offers ("Avatar" tab): the AI
// teammates and the people, those the art pack has. Other sheets of the pack
// (the hair options drawn for Helena) are left out.
export const premadeSheets = paths =>
  [
    ...Object.values(CHARACTERS).map(({ sheet }) => sheet),
    ...PEOPLE_SHEETS,
  ].filter(sheet => paths.includes(sheet));

// The sheet a teammate or person is drawn with: their own look when they
// made one in the avatar editor.
export const sheetOf = ({ avatar, sheet }) =>
  avatar ? lookSheet(avatar) : sheet;

export const ROOMS = [
  { key: 'RECEPTION', x: 8, y: 72 },
  { key: 'WAITING_ROOM', x: 8, y: 328 },
  // Top right of the gerência, clear of Helena's name over her head.
  { key: 'MANAGEMENT', x: 1272, y: 114, alignRight: true },
  { key: 'KITCHEN', x: 1272, y: 392, alignRight: true },
  { key: 'MARKETING', x: 648, y: 72 },
];

// The clinic as drawn: the fixed rooms (floor and wall areas, partition)
// plus what each clinic can change in the editor: floor and wall art,
// furniture, room names and the AI team (name, look and seat).
export const DEFAULT_LAYOUT = {
  floors: FLOORS,
  walls: WALLS,
  items: ITEMS,
  rooms: ROOMS,
  team: CHARACTERS,
};

// The reception desk used to be drawn in five pieces. Layouts saved then get
// the whole desk instead, where its left corner was (16 px taller).
const DESK_PIECES = [
  'balcao_canto_esq',
  'balcao_meio',
  'balcao_com_computador',
  'balcao_meio_2',
  'balcao_canto_dir',
].map(name => `${R}${name}.png`);
const wholeDesk = items => {
  const corner = items.find(({ sprite }) => sprite === DESK_PIECES[0]);
  if (!corner) return items;
  return [
    ...items.filter(({ sprite }) => !DESK_PIECES.includes(sprite)),
    { sprite: `${R}balcao_recepcao.png`, x: corner.x, y: corner.y - 16 },
  ];
};

// The saved layout of a clinic (only what the editor changes) on top of the
// default one. `saved` is null when the clinic never edited it.
export function applySaved(saved) {
  if (!saved) return DEFAULT_LAYOUT;
  const pick = (list, blocks) =>
    list.map((area, i) => ({ ...area, block: blocks?.[i] || area.block }));
  return {
    floors: pick(FLOORS, saved.floors),
    walls: pick(WALLS, saved.walls),
    items: saved.items ? wholeDesk(saved.items) : ITEMS,
    rooms: ROOMS.map(room => ({ ...room, name: saved.rooms?.[room.key] })),
    team: Object.fromEntries(
      Object.entries(CHARACTERS).map(([persona, spot]) => [
        persona,
        { ...spot, ...saved.team?.[persona] },
      ])
    ),
  };
}

// What goes to the API: the editable part only.
export function toSaved(layout) {
  return {
    floors: layout.floors.map(floor => floor.block),
    walls: layout.walls.map(wall => wall.block),
    items: layout.items.map(({ sprite, x, y, flip, sortY }) => ({
      sprite,
      x: Math.round(x),
      y: Math.round(y),
      ...(flip ? { flip: true } : {}),
      ...(sortY === undefined ? {} : { sortY: Math.round(sortY) }),
    })),
    rooms: Object.fromEntries(
      layout.rooms.filter(room => room.name).map(room => [room.key, room.name])
    ),
    team: Object.fromEntries(
      Object.entries(layout.team).map(([persona, spot]) => [
        persona,
        {
          ...(spot.avatar ? { avatar: spot.avatar } : { sheet: spot.sheet }),
          x: Math.round(spot.x),
          y: Math.round(spot.y),
          ...(spot.name ? { name: spot.name } : {}),
        },
      ])
    ),
  };
}

export const spritePaths = (layout = DEFAULT_LAYOUT) => [
  ...new Set([
    ...layout.floors.map(f => f.block),
    ...layout.walls.map(w => w.block),
    ...layout.items.map(i => i.sprite),
    ...GARDEN_ITEMS.map(i => i.sprite),
    ...Object.values(layout.team).map(sheetOf),
  ]),
];

export const SPRITE_PATHS = spritePaths();
