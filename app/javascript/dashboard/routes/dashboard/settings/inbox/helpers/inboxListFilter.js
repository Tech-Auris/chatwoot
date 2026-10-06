// Connection kind, as the "Conexão" filter offers it: the WhatsApp providers
// apart, the other channels by their type.
const CHANNEL_KEYS = {
  'Channel::FacebookPage': 'MESSENGER',
  'Channel::WebWidget': 'WEB_WIDGET',
  'Channel::TwitterProfile': 'TWITTER_PROFILE',
  'Channel::Sms': 'SMS',
  'Channel::Email': 'EMAIL',
  'Channel::Telegram': 'TELEGRAM',
  'Channel::Line': 'LINE',
  'Channel::Api': 'API',
  'Channel::Instagram': 'INSTAGRAM',
  'Channel::Tiktok': 'TIKTOK',
  'Channel::Voice': 'VOICE',
  'Channel::Simulator': 'SIMULATOR',
};
const WHATSAPP_PROVIDER_KEYS = {
  baileys: 'WHATSAPP_BAILEYS',
  zapi: 'WHATSAPP_ZAPI',
};

export const connectionKey = inbox => {
  if (inbox.channel_type === 'Channel::Whatsapp')
    return WHATSAPP_PROVIDER_KEYS[inbox.provider] || 'WHATSAPP_CLOUD';
  if (inbox.channel_type === 'Channel::TwilioSms')
    return inbox.medium === 'whatsapp' ? 'WHATSAPP_TWILIO' : 'TWILIO_SMS';
  return CHANNEL_KEYS[inbox.channel_type] || 'API';
};

// What the customer sees on the other side: the number, the @ or the site.
export const inboxAddress = inbox => {
  if (inbox.phone_number) return inbox.phone_number;
  if (inbox.channel_type === 'Channel::Instagram') return `@${inbox.name}`;
  if (inbox.channel_type === 'Channel::Telegram' && inbox.bot_name)
    return `@${inbox.bot_name}`;
  return inbox.website_url || inbox.email || '—';
};

const digitsOf = value => String(value || '').replace(/\D/g, '');

// Name, identification (number with or without formatting, @, site) or id.
export const matchesQuery = (inbox, query) => {
  const text = query.toLowerCase();
  if (inbox.name.toLowerCase().includes(text)) return true;
  if (inboxAddress(inbox).toLowerCase().includes(text)) return true;
  if (String(inbox.id) === query) return true;

  const digits = digitsOf(query);
  return digits.length >= 3 && digitsOf(inbox.phone_number).includes(digits);
};
