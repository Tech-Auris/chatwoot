import { describe, it, expect } from 'vitest';
import { DEFAULT_LAYOUT, ITEMS } from '../engine/layout';
import { checkLayout } from '../engine/layoutCheck';
import { SUGGESTED, hiddenAccessories, inSeason } from '../engine/seasons';

const seasons = {
  active: [
    {
      key: 'christmas',
      folder: '11_natal',
      accessory: 'Accessory_20_Gorro_Natal',
      until: '31/12',
    },
    { key: 'party', folder: '13_festa' },
  ],
  folders: ['11_natal', '12_halloween', '13_festa'],
  accessories: ['Accessory_20_Gorro_Natal', 'Accessory_24_Abobora'],
};

// The drawn size of the pack pieces (the art cropped to its outline).
const PACK_SIZES = {
  'arvore_natal.png': [60, 80],
  'presentes.png': [44, 54],
  'presente_vermelho.png': [24, 20],
  'guirlanda.png': [32, 34],
  'guirlanda_2.png': [32, 34],
  'meia_vermelha.png': [20, 30],
  'meia_listrada.png': [20, 30],
  'mini_arvore.png': [24, 38],
  'quebra_nozes.png': [30, 60],
  'biscoitos.png': [24, 24],
  'bengala_doce.png': [26, 12],
  'arvore_natal_3.png': [60, 68],
  'presente_azul.png': [20, 24],
  'aboboras.png': [52, 44],
  'abobora.png': [32, 32],
  'balde_doces.png': [32, 42],
  'teia.png': [32, 36],
  'teia_2.png': [32, 36],
  'varal_morcegos.png': [32, 12],
  'fantasma.png': [30, 64],
  'chapeu_bruxa.png': [32, 32],
  'caldeirao.png': [46, 54],
  'doces.png': [52, 40],
  'gato_preto.png': [50, 30],
  'bandeirinhas.png': [52, 14],
  'bandeirinhas_2.png': [52, 16],
  'balao_vermelho.png': [22, 58],
  'balao_azul.png': [22, 58],
  'balao_rosa.png': [22, 58],
  'presente.png': [30, 32],
  'presente_2.png': [30, 32],
  'balao_laranja.png': [26, 60],
  'balao_verde.png': [26, 60],
  'bolo.png': [38, 40],
};
const sizes = Object.fromEntries([
  ...ITEMS.map(({ sprite }) => [sprite, { width: 32, height: 32 }]),
  ...Object.values(SUGGESTED)
    .flat()
    .map(({ sprite }) => {
      const [width, height] = PACK_SIZES[sprite.split('/')[1]];
      return [sprite, { width, height }];
    }),
]);

describe('decoration packs', () => {
  it('shows the pieces of the packs in season and hides the others', () => {
    expect(inSeason('11_natal/arvore_natal.png', seasons)).toBe(true);
    expect(inSeason('13_festa/bolo.png', seasons)).toBe(true);
    expect(inSeason('12_halloween/abobora.png', seasons)).toBe(false);
    expect(inSeason('1_recepcao/lixeira.png', seasons)).toBe(true);
    expect(hiddenAccessories(seasons)).toEqual(['Accessory_24_Abobora']);
  });

  it.each(Object.keys(SUGGESTED))(
    'keeps the door and the team reachable with the %s decoration',
    key => {
      const items = [...ITEMS, ...SUGGESTED[key]];
      expect(checkLayout({ ...DEFAULT_LAYOUT, items }, sizes)).toBeNull();
    }
  );
});
