// Decoration packs (the clinic config's `seasons`: `{ active: [{ key,
// folder, accessory, until }], folders, accessories }`). Out of season the
// pieces of a pack stay saved but don't show on the map, and its avatar
// accessory is not offered; `active` also has the packs that are always on.

const folderOf = (sprite, seasons) =>
  (seasons?.folders || []).find(folder => sprite.startsWith(`${folder}/`));

export const inSeason = (sprite, seasons) => {
  const folder = folderOf(sprite, seasons);
  return !folder || seasons.active.some(season => season.folder === folder);
};

// The avatar accessories (styles) of the packs out of season.
export const hiddenAccessories = seasons =>
  (seasons?.accessories || []).filter(
    accessory => !seasons.active.some(season => season.accessory === accessory)
  );

// "Usar a decoração sugerida": where each pack goes in the default clinic.
// Wall pieces sit on the top wall; things on a table use `sortY`.
const N = '11_natal/';
const H = '12_halloween/';
const F = '13_festa/';
export const SUGGESTED = {
  christmas: [
    { sprite: `${N}arvore_natal.png`, x: 440, y: 100 },
    { sprite: `${N}presentes.png`, x: 452, y: 150 },
    { sprite: `${N}presente_vermelho.png`, x: 500, y: 170 },
    { sprite: `${N}guirlanda.png`, x: 210, y: 16 },
    { sprite: `${N}guirlanda_2.png`, x: 520, y: 16 },
    { sprite: `${N}meia_vermelha.png`, x: 340, y: 26 },
    { sprite: `${N}meia_listrada.png`, x: 362, y: 26 },
    { sprite: `${N}mini_arvore.png`, x: 142, y: 340, sortY: 408 },
    { sprite: `${N}quebra_nozes.png`, x: 556, y: 466 },
    { sprite: `${N}biscoitos.png`, x: 780, y: 478, sortY: 525 },
    { sprite: `${N}bengala_doce.png`, x: 802, y: 500, sortY: 525 },
    { sprite: `${N}arvore_natal_3.png`, x: 1196, y: 392 },
    { sprite: `${N}presente_azul.png`, x: 1236, y: 470 },
  ],
  halloween: [
    { sprite: `${H}aboboras.png`, x: 450, y: 140 },
    { sprite: `${H}abobora.png`, x: 8, y: 150 },
    { sprite: `${H}balde_doces.png`, x: 186, y: 160 },
    { sprite: `${H}teia.png`, x: 8, y: 14 },
    { sprite: `${H}teia_2.png`, x: 606, y: 12 },
    { sprite: `${H}varal_morcegos.png`, x: 210, y: 24 },
    { sprite: `${H}varal_morcegos.png`, x: 242, y: 24 },
    { sprite: `${H}fantasma.png`, x: 8, y: 410 },
    { sprite: `${H}chapeu_bruxa.png`, x: 350, y: 360, sortY: 408 },
    { sprite: `${H}caldeirao.png`, x: 556, y: 470 },
    { sprite: `${H}doces.png`, x: 773, y: 472, sortY: 525 },
    { sprite: `${H}gato_preto.png`, x: 690, y: 606 },
  ],
  party: [
    { sprite: `${F}bandeirinhas.png`, x: 140, y: 22 },
    { sprite: `${F}bandeirinhas_2.png`, x: 192, y: 22 },
    { sprite: `${F}bandeirinhas.png`, x: 496, y: 22 },
    { sprite: `${F}balao_vermelho.png`, x: 420, y: 120 },
    { sprite: `${F}balao_azul.png`, x: 442, y: 116 },
    { sprite: `${F}balao_rosa.png`, x: 464, y: 122 },
    { sprite: `${F}presente.png`, x: 500, y: 160 },
    { sprite: `${F}presente_2.png`, x: 530, y: 170 },
    { sprite: `${F}balao_laranja.png`, x: 560, y: 470 },
    { sprite: `${F}balao_verde.png`, x: 586, y: 466 },
    { sprite: `${F}bolo.png`, x: 780, y: 470, sortY: 525 },
  ],
};
