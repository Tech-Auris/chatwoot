import { connectionKey, inboxAddress, matchesQuery } from '../inboxListFilter';

const baileys = {
  id: 13,
  name: 'Teste Auris2',
  channel_type: 'Channel::Whatsapp',
  provider: 'baileys',
  phone_number: '+5511992963408',
};
const instagram = {
  id: 20,
  name: 'clinica.leger',
  channel_type: 'Channel::Instagram',
};
const site = {
  id: 1,
  name: 'Acme Support',
  channel_type: 'Channel::WebWidget',
  website_url: 'https://acme.inc',
};

describe('inboxListFilter', () => {
  it('tells the WhatsApp providers apart', () => {
    expect(connectionKey(baileys)).toBe('WHATSAPP_BAILEYS');
    expect(
      connectionKey({ channel_type: 'Channel::Whatsapp', provider: 'zapi' })
    ).toBe('WHATSAPP_ZAPI');
    expect(
      connectionKey({
        channel_type: 'Channel::Whatsapp',
        provider: 'whatsapp_cloud',
      })
    ).toBe('WHATSAPP_CLOUD');
    expect(connectionKey(site)).toBe('WEB_WIDGET');
  });

  it('shows the number, the @ or the site', () => {
    expect(inboxAddress(baileys)).toBe('+5511992963408');
    expect(inboxAddress(instagram)).toBe('@clinica.leger');
    expect(inboxAddress(site)).toBe('https://acme.inc');
  });

  it('finds an inbox by name, number with or without formatting, @, site or id', () => {
    expect(matchesQuery(baileys, 'auris2')).toBe(true);
    expect(matchesQuery(baileys, '11 99296-3408')).toBe(true);
    expect(matchesQuery(baileys, '992963408')).toBe(true);
    expect(matchesQuery(instagram, '@clinica')).toBe(true);
    expect(matchesQuery(site, 'acme.inc')).toBe(true);
    expect(matchesQuery(baileys, '13')).toBe(true);
    expect(matchesQuery(baileys, '777')).toBe(false);
    expect(matchesQuery(site, 'leger')).toBe(false);
  });
});
