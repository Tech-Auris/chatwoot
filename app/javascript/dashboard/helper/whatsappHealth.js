// Same scale as Meta's WhatsApp Manager: a dot plus Alta / Média / Baixa.
// A banned number gets a solid badge so it never reads as a plain "Baixa".
export const QUALITY_STYLES = {
  GREEN: { badge: 'bg-n-alpha-2 text-n-slate-12', dot: 'bg-n-teal-9' },
  YELLOW: { badge: 'bg-n-alpha-2 text-n-slate-12', dot: 'bg-n-amber-9' },
  RED: { badge: 'bg-n-alpha-2 text-n-slate-12', dot: 'bg-n-ruby-9' },
  BANNED: { badge: 'bg-n-ruby-9 text-white', dot: 'bg-white' },
  UNKNOWN: { badge: 'bg-n-alpha-2 text-n-slate-11', dot: 'bg-n-slate-8' },
};

// A ban lives on the number's status, not on its quality rating.
export const qualityKey = ({ quality_rating: rating, phone_status: status }) =>
  status === 'BANNED' ? 'BANNED' : rating || 'UNKNOWN';

export const qualityStyle = key =>
  QUALITY_STYLES[key] || QUALITY_STYLES.UNKNOWN;

export const accountStatusDot = status => {
  if (status === 'APPROVED') return 'bg-n-teal-9';
  if (status === 'PENDING') return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};
