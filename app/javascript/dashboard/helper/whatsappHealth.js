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

// Meta's `health_status.can_send_message`: whether the number can send now,
// covering the number, the account (WABA), the business and the app.
export const SEND_STATUS_DOTS = {
  AVAILABLE: 'bg-n-teal-9',
  LIMITED: 'bg-n-amber-9',
  BLOCKED: 'bg-n-ruby-9',
};

export const accountStatusDot = status => {
  if (status === 'APPROVED') return 'bg-n-teal-9';
  if (status === 'PENDING') return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};

// Statuses that stop a new conversation from going out of a number (the
// pencil). Meta saying the number cannot send (BLOCKED) wins; the account
// review status does not block — a REJECTED review can sit on a number that
// sends normally. Low quality alone does not block either. A number with no
// health read yet is let through.
const BLOCKING_PHONE_STATUSES = {
  BANNED: 'BANNED',
  DISCONNECTED: 'NUMBER_DISCONNECTED',
  DELETED: 'DELETED',
  PENDING: 'PENDING',
  UNVERIFIED: 'PENDING',
  RESTRICTED: 'RESTRICTED',
};

export const sendBlockReason = inbox => {
  if (inbox?.channel_type !== 'Channel::Whatsapp') return null;

  const connection = inbox.provider_connection || {};
  if (['baileys', 'zapi'].includes(inbox.provider)) {
    if (connection.connection === 'open') return null;
    return connection.connection === 'connecting'
      ? 'CONNECTING'
      : 'DISCONNECTED';
  }

  const health = connection.health;
  if (!health) return null;
  if (health.can_send_message === 'BLOCKED') return 'META_BLOCKED';
  return BLOCKING_PHONE_STATUSES[health.phone_status] || null;
};
