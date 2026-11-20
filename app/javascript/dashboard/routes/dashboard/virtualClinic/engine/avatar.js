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
