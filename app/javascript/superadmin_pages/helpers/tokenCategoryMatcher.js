// Guesses which catalog product bills each usage category, so the monthly token
// screen opens ready instead of asking for the same three choices every month.
//
// Order matters: the media product is named "Respostas a imagens, arquivos e
// transcrições de áudio", so matching audio first would claim it and leave the
// real audio product out. Media is resolved first and its product is taken out
// of the running for the others.
const CATEGORY_PATTERNS = [
  { category: 'media', pattern: /imagem|imagens|arquivo|transcri/ },
  { category: 'text', pattern: /texto/ },
  { category: 'audio', pattern: /audio/ },
];

const normalize = value =>
  (value || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

// A one-off price is what an invoice charges; the monthly price of the same
// product belongs to a subscription. Falls back to whatever exists so a product
// priced only monthly still gets picked rather than silently skipped.
const preferredPrice = prices =>
  prices.find(price => !price.recurring_interval) || prices[0];

export const matchCategoryPrices = (prices = []) => {
  const taken = new Set();
  const result = { text: '', media: '', audio: '' };

  CATEGORY_PATTERNS.forEach(({ category, pattern }) => {
    const candidates = prices.filter(
      price =>
        !taken.has(price.product_id) &&
        pattern.test(normalize(price.product_name))
    );
    if (!candidates.length) return;

    const chosen = preferredPrice(
      candidates.filter(price => price.product_id === candidates[0].product_id)
    );
    taken.add(chosen.product_id);
    result[category] = chosen.id;
  });

  return result;
};
