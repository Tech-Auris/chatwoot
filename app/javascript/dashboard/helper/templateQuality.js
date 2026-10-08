import { QUALITY_STYLES } from 'dashboard/helper/whatsappHealth';

// Meta rates each template by how patients react to it (blocks, reports,
// reads). A paused or disabled template is refused by Meta whatever its
// rating, so that state wins over the score.
export const TEMPLATE_QUALITY_STYLES = {
  ...QUALITY_STYLES,
  PAUSED: { badge: 'bg-n-ruby-3 text-n-ruby-11', dot: 'bg-n-ruby-9' },
  DISABLED: { badge: 'bg-n-ruby-9 text-white', dot: 'bg-white' },
};

const SCORES = ['GREEN', 'YELLOW', 'RED'];

export const templateScore = template => {
  const score = template?.quality_score?.score;
  return SCORES.includes(score) ? score : 'UNKNOWN';
};

export const templateQualityKey = template => {
  const status = (template?.status || '').toUpperCase();
  if (['PAUSED', 'DISABLED'].includes(status)) return status;
  return templateScore(template);
};

export const templateQualityStyle = key =>
  TEMPLATE_QUALITY_STYLES[key] || TEMPLATE_QUALITY_STYLES.UNKNOWN;

// Média, Baixa, Pausado and Desativado get the warning with suggestions; a
// template Meta has not rated yet does not.
export const templateQualityWarns = key =>
  ['YELLOW', 'RED', 'PAUSED', 'DISABLED'].includes(key);

// Campaigns refuse what would hurt the number the most.
export const templateQualityBlocksCampaign = key =>
  ['RED', 'PAUSED', 'DISABLED'].includes(key);

// Meta sends the evaluation date in seconds.
export const templateQualityDate = template => {
  const date = template?.quality_score?.date;
  return date ? new Date(date * 1000) : null;
};
