import { describe, it, expect } from 'vitest';
import {
  avatarCatalog,
  avatarKey,
  colorsOf,
  isAvatarKey,
  PREMADE_LOOKS,
  layersOf,
  lookSheet,
  optionsOf,
  premadeSheets,
  randomAvatar,
} from '../engine/avatar';
import {
  CHARACTERS,
  DEFAULT_LAYOUT,
  PEOPLE_SHEETS,
  sheetOf,
  toSaved,
} from '../engine/layout';

const paths = [
  '5_pisos/madeira.png',
  '9_avatar/Body_32x32_01.png',
  '9_avatar/Body_32x32_02.png',
  '9_avatar/Eyes_32x32_01.png',
  '9_avatar/Outfit_01_32x32_01.png',
  '9_avatar/Outfit_02_32x32_01.png',
  '9_avatar/Outfit_02_32x32_02.png',
  '9_avatar/Hairstyle_01_32x32_01.png',
  '9_avatar/Hairstyle_01_32x32_03.png',
  '9_avatar/Hairstyle_02_32x32_01.png',
  '9_avatar/Hairstyle_02_32x32_03.png',
  '9_avatar/Accessory_15_Glasses_32x32_01.png',
  '9_avatar/Smartphone_32x32_1.png',
];
const catalog = avatarCatalog(paths);
const look = {
  body: 'Body_32x32_02',
  eyes: 'Eyes_32x32_01',
  outfit: 'Outfit_02_32x32_02',
  hair: 'Hairstyle_01_32x32_03',
};

describe('avatar looks', () => {
  it('groups the generator layers by part, style and color', () => {
    expect(catalog.body).toEqual([
      { style: 'Body', colors: ['Body_32x32_01', 'Body_32x32_02'] },
    ]);
    expect(catalog.outfit.map(({ style }) => style)).toEqual([
      'Outfit_01',
      'Outfit_02',
    ]);
    expect(catalog.accessory[0].style).toBe('Accessory_15_Glasses');
  });

  it('lists the colors in the grid for skin, and styles with dots for hair', () => {
    expect(optionsOf(catalog, 'body', look)).toEqual([
      'Body_32x32_01',
      'Body_32x32_02',
    ]);
    expect(colorsOf(catalog, 'body', look)).toEqual([]);
    // Each hairstyle in the hair color picked now.
    expect(optionsOf(catalog, 'hair', look)).toEqual([
      'Hairstyle_01_32x32_03',
      'Hairstyle_02_32x32_03',
    ]);
    expect(colorsOf(catalog, 'hair', look)).toEqual([
      'Hairstyle_01_32x32_01',
      'Hairstyle_01_32x32_03',
    ]);
    expect(optionsOf(catalog, 'outfit', look)).toEqual([
      'Outfit_01_32x32_01',
      'Outfit_02_32x32_02',
    ]);
  });

  it('turns a look into a sheet key with its layers, phone on top', () => {
    const key = avatarKey(look);
    expect(isAvatarKey(key)).toBe(true);
    expect(isAvatarKey('8_pessoas/pessoa_01.png')).toBe(false);
    expect(layersOf(key)).toEqual([
      'Body_32x32_02',
      'Eyes_32x32_01',
      'Outfit_02_32x32_02',
      'Hairstyle_01_32x32_03',
      'Smartphone_32x32_1',
    ]);
  });

  it('draws a premade character with its own sheet and lists them', () => {
    expect(lookSheet({ sheet: '8_pessoas/pessoa_03.png' })).toBe(
      '8_pessoas/pessoa_03.png'
    );
    expect(lookSheet(look)).toBe(avatarKey(look));
    expect(
      premadeSheets([
        '7_personagens/clara_secretaria.png',
        '7_personagens/clara_secretaria_spritesheet.png',
        '8_pessoas/pessoa_03.png',
        '9_avatar/Body_32x32_01.png',
      ])
    ).toEqual([
      '7_personagens/clara_secretaria_spritesheet.png',
      '8_pessoas/pessoa_03.png',
    ]);
  });

  it('knows the parts of every premade character the clinic uses', () => {
    const sheets = [
      ...PEOPLE_SHEETS,
      ...Object.values(CHARACTERS).map(({ sheet }) => sheet),
    ];
    sheets.forEach(sheet => {
      expect(PREMADE_LOOKS[sheet]).toMatchObject({
        body: expect.stringMatching(/^Body_/),
        eyes: expect.stringMatching(/^Eyes_/),
        outfit: expect.stringMatching(/^Outfit_/),
      });
    });
  });

  it('makes a random look with every required part', () => {
    const random = randomAvatar(catalog, () => 0.99);
    expect(random).toMatchObject({
      body: 'Body_32x32_02',
      eyes: 'Eyes_32x32_01',
      outfit: 'Outfit_02_32x32_02',
      hair: 'Hairstyle_02_32x32_03',
    });
  });

  it('draws a teammate with their look and saves it instead of the art', () => {
    const team = {
      ...DEFAULT_LAYOUT.team,
      secretary: { ...DEFAULT_LAYOUT.team.secretary, avatar: look },
    };
    expect(sheetOf(team.secretary)).toBe(avatarKey(look));
    expect(sheetOf(team.manager)).toBe(DEFAULT_LAYOUT.team.manager.sheet);

    const saved = toSaved({ ...DEFAULT_LAYOUT, team });
    expect(saved.team.secretary).toEqual({ avatar: look, x: 304, y: 87 });
    expect(saved.team.manager.sheet).toBe(DEFAULT_LAYOUT.team.manager.sheet);
  });
});
