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

// Floors repeat a 3×2-tile block; walls are 2 tiles high and repeat the
// middle column of their 3×2 block.
export const FLOORS = [
  {
    block: '5_pisos/porcelanato_branco_recepcao.png',
    x: 0,
    y: 64,
    w: 512,
    h: 256,
  },
  { block: '5_pisos/piso_azul_claro_espera.png', x: 0, y: 320, w: 512, h: 320 },
  { block: '5_pisos/madeira_gerencia.png', x: 512, y: 64, w: 448, h: 256 },
  { block: '5_pisos/xadrez_cinza_copa.png', x: 512, y: 384, w: 448, h: 256 },
];

export const WALLS = [
  { block: '6_paredes/azul_com_cruz_recepcao_espera.png', x: 0, y: 0, w: 512 },
  { block: '6_paredes/bege_gerencia.png', x: 512, y: 0, w: 448 },
  { block: '6_paredes/azulejo_branco_copa.png', x: 512, y: 320, w: 448 },
];

// The wall between the two wings, with the two passages
// (recepção ↔ gerência and espera ↔ copa).
export const PARTITION = {
  x: 508,
  width: 8,
  gaps: [
    [192, 256],
    [480, 544],
  ],
};

// `sortY` overrides the depth (bottom edge) for things standing on a desk;
// `flip` mirrors the sprite.
export const ITEMS = [
  // Recepção
  { sprite: `${R}porta_vidro_entrada.png`, x: 32, y: 14 },
  { sprite: `${R}relogio.png`, x: 230, y: 15 },
  { sprite: `${R}quadro_cruz.png`, x: 308, y: 15 },
  { sprite: `${R}quadro_avisos.png`, x: 359, y: 15 },
  { sprite: `${R}flores_gaveteiro.png`, x: 140, y: 45 },
  { sprite: `${R}planta_grande.png`, x: 435, y: 45 },
  { sprite: `${R}cadeira_secretaria.png`, x: 240, y: 104 },
  { sprite: `${R}balcao_canto_esq.png`, x: 128, y: 133 },
  { sprite: `${R}balcao_meio.png`, x: 160, y: 165 },
  { sprite: `${R}balcao_com_computador.png`, x: 192, y: 161 },
  { sprite: `${R}balcao_meio_2.png`, x: 256, y: 165 },
  { sprite: `${R}balcao_canto_dir.png`, x: 288, y: 133 },
  { sprite: `${R}lixeira.png`, x: 385, y: 210 },
  { sprite: `${R}planta_media.png`, x: 10, y: 237 },
  // Sala de espera
  { sprite: `${E}poltronas_beges_dupla.png`, x: 20, y: 352 },
  { sprite: `${E}mesinha_revistas.png`, x: 118, y: 367 },
  { sprite: `${E}poltronas_verdes_dupla.png`, x: 198, y: 352 },
  { sprite: `${E}mesinha_revistas_2.png`, x: 297, y: 367 },
  { sprite: `${E}poltronas_beges_dupla.png`, x: 377, y: 352 },
  { sprite: `${E}bebedouro.png`, x: 478, y: 427 },
  ...[32, 65, 98, 131, 164, 300, 333, 366, 399, 432].map(x => ({
    sprite: `${E}cadeira_azul_costas.png`,
    x,
    y: 530,
  })),
  { sprite: `${E}flores_gaveteiro.png`, x: 220, y: 555 },
  { sprite: `${E}planta.png`, x: 7, y: 580 },
  { sprite: `${E}planta.png`, x: 474, y: 580 },
  // Gerência
  { sprite: `${G}quadro_graficos.png`, x: 544, y: 8 },
  { sprite: `${G}diploma.png`, x: 691, y: 17 },
  { sprite: `${G}diploma_2.png`, x: 723, y: 17 },
  { sprite: `${G}diploma_3.png`, x: 755, y: 17 },
  { sprite: `${G}arquivo.png`, x: 838, y: 35 },
  { sprite: `${G}arquivo_2.png`, x: 873, y: 35 },
  { sprite: `${G}planta.png`, x: 915, y: 52 },
  { sprite: `${G}cadeira_executiva_frente.png`, x: 672, y: 78 },
  { sprite: `${G}mesa_em_l.png`, x: 655, y: 131 },
  { sprite: `${G}monitor_duplo.png`, x: 655, y: 122, sortY: 196 },
  { sprite: `${G}luminaria.png`, x: 755, y: 129 },
  { sprite: `${G}planta_2.png`, x: 523, y: 245 },
  { sprite: `${G}sofa.png`, x: 819, y: 236 },
  // Copa
  { sprite: `${C}geladeira.png`, x: 525, y: 332 },
  { sprite: `${C}maquina_lanches.png`, x: 585, y: 340 },
  { sprite: `${C}maquina_bebidas.png`, x: 637, y: 340 },
  { sprite: `${C}cafeteira_bancada.png`, x: 710, y: 360 },
  { sprite: `${C}maquina_cafe.png`, x: 774, y: 340 },
  { sprite: `${C}bebedouro.png`, x: 841, y: 355 },
  { sprite: `${C}cadeira_frente.png`, x: 698, y: 435 },
  { sprite: `${C}mesa_redonda.png`, x: 682, y: 460 },
  { sprite: `${C}cadeira_lado.png`, x: 652, y: 482 },
  { sprite: `${C}cadeira_lado.png`, x: 744, y: 482, flip: true },
  { sprite: `${C}planta.png`, x: 523, y: 585 },
  { sprite: `${C}lixeira.png`, x: 919, y: 592 },
];

// Where each AI teammate stands (top-left of the 32×64 frame), where its
// balloon and name tag go, and its spritesheet.
export const CHARACTERS = {
  secretary: {
    sheet: '7_personagens/clara_secretaria_spritesheet.png',
    x: 240,
    y: 87,
    bubble: { x: 256, y: 104 },
    tag: { x: 256, y: 214 },
  },
  manager: {
    sheet: '7_personagens/helena_opcao_A_spritesheet.png',
    x: 672,
    y: 60,
    bubble: { x: 688, y: 76 },
    tag: { x: 688, y: 214 },
  },
};

export const ROOMS = [
  { key: 'RECEPTION', x: 8, y: 72 },
  { key: 'WAITING_ROOM', x: 8, y: 328 },
  { key: 'MANAGEMENT', x: 524, y: 72 },
  { key: 'KITCHEN', x: 870, y: 420 },
];

export const SPRITE_PATHS = [
  ...new Set([
    ...FLOORS.map(f => f.block),
    ...WALLS.map(w => w.block),
    ...ITEMS.map(i => i.sprite),
    ...Object.values(CHARACTERS).map(c => c.sheet),
  ]),
];
