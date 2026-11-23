// Avatars, Gather-style. A look is either a premade character of the pack
// (`{ sheet: '8_pessoas/pessoa_03.png' }`) or built from the layers of the
// LimeZu character generator (art folder `9_avatar/`): `{ body, eyes,
// outfit, hair, accessory }`, each the name of one layer
// ("Hairstyle_04_32x32_03"), drawn in this order on top of each other. Hair
// and accessory may be left out.
export const AVATAR_FOLDER = '9_avatar';
export const PARTS = [
  { key: 'body', prefix: 'Body_' },
  { key: 'eyes', prefix: 'Eyes_' },
  { key: 'outfit', prefix: 'Outfit_' },
  { key: 'hair', prefix: 'Hairstyle_', optional: true },
  { key: 'accessory', prefix: 'Accessory_', optional: true },
];
// Drawn on top of every look: the phone of the "on a call" frames.
const PHONE = 'Smartphone_32x32_1';
const KEY_PREFIX = 'avatar:';

export const layerPath = name => `${AVATAR_FOLDER}/${name}.png`;

// The look as a sprite key, standing in for a spritesheet path: the
// renderer and the sprite loader use it like any other sheet.
export const avatarKey = avatar =>
  KEY_PREFIX + PARTS.map(({ key }) => avatar[key] || '').join(',');
export const isAvatarKey = key => key.startsWith(KEY_PREFIX);
// The sheet any look is drawn with.
export const lookSheet = look => look.sheet || avatarKey(look);

// The premade characters the editor offers ("Avatar" tab).
export const premadeSheets = paths =>
  paths.filter(path =>
    /^(7_personagens\/.+_spritesheet|8_pessoas\/.+)\.png$/.test(path)
  );
export const layersOf = key => [
  ...key.slice(KEY_PREFIX.length).split(',').filter(Boolean),
  PHONE,
];

// "Hairstyle_04_32x32_03" → { style: 'Hairstyle_04', color: '03' }; bodies
// and eyes only come in colors ("Body_32x32_07" → style 'Body').
export const splitLayer = name => {
  const [style, color] = name.split('_32x32_');
  return { style, color };
};

// What the editor offers, from the art list: per part, its styles and the
// colors of each style (layer names).
export function avatarCatalog(paths) {
  const names = paths
    .filter(path => path.startsWith(`${AVATAR_FOLDER}/`))
    .map(path => path.slice(AVATAR_FOLDER.length + 1, -'.png'.length));
  return Object.fromEntries(
    PARTS.map(({ key, prefix }) => {
      const styles = {};
      names
        .filter(name => name.startsWith(prefix) && name.includes('_32x32_'))
        .sort()
        .forEach(name => {
          const { style } = splitLayer(name);
          styles[style] = [...(styles[style] || []), name];
        });
      return [
        key,
        Object.entries(styles).map(([style, colors]) => ({ style, colors })),
      ];
    })
  );
}

// The choices shown in the grid of a part: every color when the part has a
// single style (skin, eyes), otherwise one per style, in the color picked
// now when that style has it.
export function optionsOf(catalog, part, avatar) {
  const styles = catalog[part] || [];
  if (styles.length === 1) return styles[0].colors;
  const color = avatar[part] && splitLayer(avatar[part]).color;
  return styles.map(
    ({ colors }) =>
      colors.find(name => splitLayer(name).color === color) || colors[0]
  );
}

// The colors of the style picked now (the dots under the grid); none for a
// part whose grid already lists the colors.
export function colorsOf(catalog, part, avatar) {
  const styles = catalog[part] || [];
  if (styles.length < 2 || !avatar[part]) return [];
  const { style } = splitLayer(avatar[part]);
  return styles.find(entry => entry.style === style)?.colors || [];
}

// What each premade character of the pack is made of (worked out by matching
// its pixels with the generator layers), so the editor changes one part of
// the character you are wearing. A few premades carry a second accessory
// (a mustache, glasses) that one accessory slot can't keep.
export const PREMADE_LOOKS = {
  '7_personagens/clara_secretaria_spritesheet.png': {
    body: 'Body_32x32_03',
    eyes: 'Eyes_32x32_05',
    outfit: 'Outfit_33_32x32_03',
    hair: 'Hairstyle_25_32x32_02',
  },
  '7_personagens/helena_gerente_spritesheet.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_05_32x32_02',
    hair: 'Hairstyle_24_32x32_03',
  },
  '7_personagens/helena_opcao_A_spritesheet.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_05_32x32_02',
    hair: 'Hairstyle_04_32x32_03',
  },
  '7_personagens/helena_opcao_B_spritesheet.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_05_32x32_02',
    hair: 'Hairstyle_09_32x32_03',
  },
  '7_personagens/helena_opcao_C_spritesheet.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_05_32x32_02',
    hair: 'Hairstyle_15_32x32_03',
  },
  '7_personagens/luciano_marketing_spritesheet.png': {
    body: 'Body_32x32_04',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_06_32x32_03',
    hair: 'Hairstyle_18_32x32_03',
  },
  '8_pessoas/pessoa_01.png': {
    body: 'Body_32x32_01',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_01_32x32_02',
    hair: 'Hairstyle_04_32x32_03',
  },
  '8_pessoas/pessoa_02.png': {
    body: 'Body_32x32_01',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_05_32x32_01',
    hair: 'Hairstyle_09_32x32_03',
  },
  '8_pessoas/pessoa_03.png': {
    body: 'Body_32x32_01',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_01_32x32_05',
    hair: 'Hairstyle_08_32x32_03',
  },
  '8_pessoas/pessoa_04.png': {
    body: 'Body_32x32_01',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_07_32x32_03',
    hair: 'Hairstyle_14_32x32_06',
    accessory: 'Accessory_11_Beanie_32x32_05',
  },
  '8_pessoas/pessoa_05.png': {
    body: 'Body_32x32_02',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_01_32x32_01',
    hair: 'Hairstyle_01_32x32_07',
  },
  '8_pessoas/pessoa_06.png': {
    body: 'Body_32x32_02',
    eyes: 'Eyes_32x32_02',
    outfit: 'Outfit_02_32x32_03',
    hair: 'Hairstyle_07_32x32_03',
  },
  '8_pessoas/pessoa_07.png': {
    body: 'Body_32x32_02',
    eyes: 'Eyes_32x32_03',
    outfit: 'Outfit_10_32x32_02',
    hair: 'Hairstyle_10_32x32_06',
    accessory: 'Accessory_11_Beanie_32x32_04',
  },
  '8_pessoas/pessoa_08.png': {
    body: 'Body_32x32_02',
    eyes: 'Eyes_32x32_03',
    outfit: 'Outfit_18_32x32_02',
    hair: 'Hairstyle_21_32x32_02',
    accessory: 'Accessory_16_Monocle_32x32_01',
  },
  '8_pessoas/pessoa_09.png': {
    body: 'Body_32x32_03',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_19_32x32_02',
    hair: 'Hairstyle_26_32x32_06',
  },
  '8_pessoas/pessoa_10.png': {
    body: 'Body_32x32_03',
    eyes: 'Eyes_32x32_05',
    outfit: 'Outfit_11_32x32_04',
    hair: 'Hairstyle_16_32x32_03',
    accessory: 'Accessory_03_Backpack_32x32_01',
  },
  '8_pessoas/pessoa_11.png': {
    body: 'Body_32x32_03',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_01_32x32_10',
    hair: 'Hairstyle_01_32x32_06',
    accessory: 'Accessory_04_Snapback_32x32_06',
  },
  '8_pessoas/pessoa_12.png': {
    body: 'Body_32x32_04',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_01_32x32_09',
    hair: 'Hairstyle_03_32x32_03',
  },
  '8_pessoas/pessoa_13.png': {
    body: 'Body_32x32_04',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_17_32x32_01',
    hair: 'Hairstyle_12_32x32_05',
    accessory: 'Accessory_15_Glasses_32x32_06',
  },
  '8_pessoas/pessoa_14.png': {
    body: 'Body_32x32_04',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_06_32x32_03',
    hair: 'Hairstyle_18_32x32_03',
  },
  '8_pessoas/pessoa_15.png': {
    body: 'Body_32x32_04',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_09_32x32_03',
    accessory: 'Accessory_09_Zombie_Brain_32x32_01',
  },
  '8_pessoas/pessoa_16.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_06',
    outfit: 'Outfit_10_32x32_04',
    hair: 'Hairstyle_23_32x32_07',
    accessory: 'Accessory_04_Snapback_32x32_05',
  },
  '8_pessoas/pessoa_17.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_06',
    outfit: 'Outfit_29_32x32_03',
    hair: 'Hairstyle_22_32x32_03',
    accessory: 'Accessory_06_Policeman_Hat_32x32_01',
  },
  '8_pessoas/pessoa_18.png': {
    body: 'Body_32x32_07',
    eyes: 'Eyes_32x32_01',
    outfit: 'Outfit_14_32x32_03',
    hair: 'Hairstyle_20_32x32_06',
    accessory: 'Accessory_03_Backpack_32x32_10',
  },
};

// A random look; hair always, accessory now and then.
export function randomAvatar(catalog, random = Math.random) {
  const pick = list => list[Math.floor(random() * list.length)];
  const avatar = {};
  PARTS.forEach(({ key }) => {
    const styles = catalog[key] || [];
    if (!styles.length || (key === 'accessory' && random() < 0.7)) return;
    avatar[key] = pick(pick(styles).colors);
  });
  return avatar;
}

// Draws a look into one spritesheet. `loadImage(path)` resolves to the
// image of one layer.
export async function composeAvatar(key, loadImage) {
  const layers = await Promise.all(
    layersOf(key).map(name => loadImage(layerPath(name)))
  );
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(...layers.map(layer => layer.width));
  canvas.height = Math.max(...layers.map(layer => layer.height));
  const context = canvas.getContext('2d');
  layers.forEach(layer => context.drawImage(layer, 0, 0));
  return canvas;
}
