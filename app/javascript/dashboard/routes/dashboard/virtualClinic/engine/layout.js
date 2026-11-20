import { lookSheet } from './avatar';

// The Clínica virtual (MVP: the same clinic for every account), from the
// approved draft: a 30×20 grid of 32 px tiles. Coordinates are world
// pixels; item positions are the top-left of the sprite cropped to its
// outline. Art comes from the LimeZu pack, served by the API (never in git).
export const TILE = 32;
export const WORLD = { width: 30 * TILE, height: 20 * TILE };

const R = '1_recepcao/';
const E = '2_sala_de_espera/';
const G = '3_gerencia/';
const C = '4_copa/';

// The clinic wing (recepção + sala de espera) takes 20 columns; the
// gerência and the copa share the other 10, so they read as smaller rooms.
const WING = 640;

// Floors repeat a 3×2-tile block; walls are 2 tiles high and repeat the
// middle column of their 3×2 block.
export const FLOORS = [
  {
    block: '5_pisos/porcelanato_branco_recepcao.png',
    x: 0,
    y: 64,
    w: WING,
    h: 256,
  },
  {
    block: '5_pisos/piso_azul_claro_espera.png',
    x: 0,
    y: 320,
    w: WING,
    h: 320,
  },
  { block: '5_pisos/madeira_gerencia.png', x: WING, y: 64, w: 320, h: 256 },
  { block: '5_pisos/xadrez_cinza_copa.png', x: WING, y: 384, w: 320, h: 256 },
];

export const WALLS = [
  { block: '6_paredes/azul_com_cruz_recepcao_espera.png', x: 0, y: 0, w: WING },
  { block: '6_paredes/bege_gerencia.png', x: WING, y: 0, w: 320 },
  { block: '6_paredes/azulejo_branco_copa.png', x: WING, y: 320, w: 320 },
];

// The wall between the two wings, with the two passages
// (recepção ↔ gerência and espera ↔ copa).
export const PARTITION = {
  x: WING - 4,
  width: 8,
  gaps: [
    [192, 256],
    [480, 544],
  ],
};

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
  { sprite: `${R}balcao_canto_esq.png`, x: 224, y: 133 },
  { sprite: `${R}balcao_meio.png`, x: 256, y: 165 },
  { sprite: `${R}balcao_com_computador.png`, x: 288, y: 161 },
  { sprite: `${R}balcao_meio_2.png`, x: 352, y: 165 },
  { sprite: `${R}balcao_canto_dir.png`, x: 384, y: 133 },
  { sprite: `${R}lixeira.png`, x: 500, y: 210 },
  { sprite: `${R}planta_media.png`, x: 12, y: 237 },
  { sprite: `${R}planta_media.png`, x: 596, y: 237 },
  // Sala de espera
  { sprite: `${E}poltronas_beges_dupla.png`, x: 28, y: 352 },
  { sprite: `${E}mesinha_revistas.png`, x: 130, y: 367 },
  { sprite: `${E}poltronas_verdes_dupla.png`, x: 236, y: 352 },
  { sprite: `${E}mesinha_revistas_2.png`, x: 342, y: 367 },
  { sprite: `${E}poltronas_beges_dupla.png`, x: 440, y: 352 },
  { sprite: `${E}bebedouro.png`, x: 600, y: 427 },
  ...chairsRow([48, 81, 114, 147, 180, 213]),
  ...chairsRow([380, 413, 446, 479, 512, 545]),
  { sprite: `${E}flores_gaveteiro.png`, x: 300, y: 555 },
  { sprite: `${E}planta.png`, x: 8, y: 580 },
  { sprite: `${E}planta.png`, x: 596, y: 580 },
  // Gerência
  { sprite: `${G}quadro_graficos.png`, x: 652, y: 8 },
  { sprite: `${G}diploma.png`, x: 728, y: 17 },
  { sprite: `${G}diploma_2.png`, x: 760, y: 17 },
  { sprite: `${G}diploma_3.png`, x: 792, y: 17 },
  { sprite: `${G}arquivo.png`, x: 848, y: 35 },
  { sprite: `${G}arquivo_2.png`, x: 882, y: 35 },
  { sprite: `${G}planta.png`, x: 920, y: 52 },
  { sprite: `${G}cadeira_executiva_frente.png`, x: 708, y: 108 },
  { sprite: `${G}mesa_reta.png`, x: 676, y: 158 },
  { sprite: `${G}mesa_em_l.png`, x: 740, y: 132 },
  // Two monitors seen from behind, facing Helena.
  { sprite: `${G}monitor_costas.png`, x: 690, y: 150, sortY: 197 },
  { sprite: `${G}monitor_costas.png`, x: 719, y: 150, sortY: 197 },
  { sprite: `${G}luminaria.png`, x: 772, y: 116, sortY: 197 },
  { sprite: `${G}planta_2.png`, x: 648, y: 250 },
  { sprite: `${G}sofa_lateral.png`, x: 928, y: 196 },
  // Copa
  { sprite: `${C}geladeira.png`, x: 648, y: 332 },
  { sprite: `${C}maquina_bebidas.png`, x: 706, y: 340 },
  { sprite: `${C}cafeteira_bancada.png`, x: 760, y: 360 },
  { sprite: `${C}maquina_cafe.png`, x: 816, y: 340 },
  { sprite: `${C}bebedouro.png`, x: 870, y: 355 },
  { sprite: `${C}cadeira_frente.png`, x: 788, y: 445 },
  { sprite: `${C}mesa_redonda.png`, x: 772, y: 470 },
  // Side chairs face the table: the left one is mirrored.
  { sprite: `${C}cadeira_lado.png`, x: 748, y: 492, flip: true },
  { sprite: `${C}cadeira_lado.png`, x: 828, y: 492 },
  { sprite: `${C}planta.png`, x: 648, y: 590 },
  { sprite: `${C}lixeira.png`, x: 920, y: 592 },
];

// Where each AI teammate sits (top-left of the 32×64 frame) and their
// spritesheet. Name and status are drawn over the head, wherever they are.
// A clinic can give them a look of its own in the avatar editor (`avatar`,
// which then wins over `sheet`).
export const CHARACTERS = {
  secretary: {
    sheet: '7_personagens/clara_secretaria_spritesheet.png',
    x: 304,
    y: 87,
  },
  manager: {
    sheet: '7_personagens/helena_opcao_A_spritesheet.png',
    x: 708,
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

// The sheet a teammate or person is drawn with: their own look when they
// made one in the avatar editor.
export const sheetOf = ({ avatar, sheet }) =>
  avatar ? lookSheet(avatar) : sheet;

// What the avatar editor builds on when a teammate still in the premade art
// gets a part changed: Helena is made of these very layers.
export const TEAM_AVATARS = {
  secretary: {
    body: 'Body_32x32_02',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_33_32x32_01',
    hair: 'Hairstyle_08_32x32_01',
  },
  manager: {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_05_32x32_02',
    hair: 'Hairstyle_04_32x32_03',
  },
};

export const ROOMS = [
  { key: 'RECEPTION', x: 8, y: 72 },
  { key: 'WAITING_ROOM', x: 8, y: 328 },
  // Top right of the gerência, clear of Helena's name over her head.
  { key: 'MANAGEMENT', x: 952, y: 114, alignRight: true },
  { key: 'KITCHEN', x: 886, y: 430 },
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

// The saved layout of a clinic (only what the editor changes) on top of the
// default one. `saved` is null when the clinic never edited it.
export function applySaved(saved) {
  if (!saved) return DEFAULT_LAYOUT;
  const pick = (list, blocks) =>
    list.map((area, i) => ({ ...area, block: blocks?.[i] || area.block }));
  return {
    floors: pick(FLOORS, saved.floors),
    walls: pick(WALLS, saved.walls),
    items: saved.items || ITEMS,
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
    ...Object.values(layout.team).map(sheetOf),
  ]),
];

export const SPRITE_PATHS = spritePaths();
