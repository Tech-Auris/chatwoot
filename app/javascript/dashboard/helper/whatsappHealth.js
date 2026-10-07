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

// `startsConversation`: the pencil and campaigns open a conversation, which a
// RESTRICTED number (new-contact limit reached) cannot do; replying in an open
// conversation it still can.
export const sendBlockReason = (inbox, { startsConversation = true } = {}) => {
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
  if (health.phone_status === 'RESTRICTED' && !startsConversation) return null;
  return BLOCKING_PHONE_STATUSES[health.phone_status] || null;
};

// Meta's own reasons and fixes when it blocks the number (Saúde da conta keeps
// them with the number's health).
export const metaBlockErrors = inbox =>
  inbox?.provider_connection?.health?.health_errors || [];

// New conversations a number may open in 24h, from Meta's
// `messaging_limit_tier`. Unlimited and unknown tiers give no limit.
const DAILY_LIMITS = {
  TIER_50: 50,
  TIER_250: 250,
  TIER_1K: 1000,
  TIER_2K: 2000,
  TIER_10K: 10000,
  TIER_100K: 100000,
};

// What a campaign should know about its number before going out, without
// blocking it: Meta limiting the sends, the quality rating, and an audience
// past the daily limit.
export const campaignWarnings = (inbox, audienceCount = 0) => {
  const health = inbox?.provider_connection?.health;
  if (!health) return [];

  const warnings = [];
  if (health.can_send_message === 'LIMITED') {
    warnings.push({
      key: 'LIMITED',
      details: metaBlockErrors(inbox).map(error => error.error_description),
    });
  }
  if (health.quality_rating === 'RED') warnings.push({ key: 'QUALITY_LOW' });
  if (health.quality_rating === 'YELLOW') {
    warnings.push({ key: 'QUALITY_MEDIUM' });
  }
  const limit = DAILY_LIMITS[health.messaging_limit_tier];
  if (limit && audienceCount > limit) {
    warnings.push({
      key: 'OVER_DAILY_LIMIT',
      params: { count: audienceCount, limit },
    });
  }
  return warnings;
};
