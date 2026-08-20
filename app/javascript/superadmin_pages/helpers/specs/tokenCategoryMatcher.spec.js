import { matchCategoryPrices } from '../tokenCategoryMatcher';

const price = (id, productId, productName, recurring = null) => ({
  id,
  product_id: productId,
  product_name: productName,
  recurring_interval: recurring,
  unit_amount: 10,
});

describe('matchCategoryPrices', () => {
  // The catalog as it exists today: each product priced both one-off and
  // monthly, with the same amount.
  const catalog = [
    price('price_texto_avulso', 'prod_texto', 'Mensagens de Texto'),
    price('price_texto_mensal', 'prod_texto', 'Mensagens de Texto', 'month'),
    price(
      'price_midia_avulso',
      'prod_midia',
      'Respostas a imagens, arquivos e transcrições de áudio'
    ),
    price(
      'price_midia_mensal',
      'prod_midia',
      'Respostas a imagens, arquivos e transcrições de áudio',
      'month'
    ),
    price('price_audio_avulso', 'prod_audio', 'Mensagens de Áudio'),
    price('price_audio_mensal', 'prod_audio', 'Mensagens de Áudio', 'month'),
  ];

  it('matches each category to its product', () => {
    expect(matchCategoryPrices(catalog)).toEqual({
      text: 'price_texto_avulso',
      media: 'price_midia_avulso',
      audio: 'price_audio_avulso',
    });
  });

  // The media product is literally named "...transcrições de áudio", so a naive
  // audio match claims it and the real audio product is left out.
  it('does not let the media product be taken for the audio one', () => {
    const withoutText = catalog.filter(p => p.product_id !== 'prod_texto');

    const matched = matchCategoryPrices(withoutText);

    expect(matched.media).toBe('price_midia_avulso');
    expect(matched.audio).toBe('price_audio_avulso');
  });

  it('prefers the one-off price over the monthly one', () => {
    const monthlyFirst = [
      price('price_mensal', 'prod_texto', 'Mensagens de Texto', 'month'),
      price('price_avulso', 'prod_texto', 'Mensagens de Texto'),
    ];

    expect(matchCategoryPrices(monthlyFirst).text).toBe('price_avulso');
  });

  it('still picks a product priced only monthly', () => {
    const onlyMonthly = [
      price('price_mensal', 'prod_texto', 'Mensagens de Texto', 'month'),
    ];

    expect(matchCategoryPrices(onlyMonthly).text).toBe('price_mensal');
  });

  it('leaves a category empty when nothing in the catalog matches it', () => {
    expect(matchCategoryPrices([price('p1', 'prod_x', 'Plano Pro')])).toEqual({
      text: '',
      media: '',
      audio: '',
    });
  });
});
