import { mount } from '@vue/test-utils';
import format from 'date-fns/format';
import WhatsappNumberMissingBanner from '../WhatsappNumberMissingBanner.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, params) => `${key} ${JSON.stringify(params)}` }),
}));

const BannerStub = {
  props: ['bannerMessage', 'colorScheme'],
  template: '<div role="alert">{{ bannerMessage }}</div>',
};

const mountBanner = checkedAt =>
  mount(WhatsappNumberMissingBanner, {
    props: { checkedAt },
    global: { stubs: { Banner: BannerStub } },
  });

describe('WhatsappNumberMissingBanner', () => {
  it('shows the warning with the date of the check', () => {
    const checkedAt = 1792684800;
    const text = mountBanner(checkedAt).text();

    expect(text).toContain('CONVERSATION.WHATSAPP_NUMBER_MISSING_BANNER');
    expect(text).toContain(
      format(new Date(checkedAt * 1000), 'dd/MM/yyyy HH:mm')
    );
  });

  it('shows nothing when the number is not flagged', () => {
    expect(mountBanner(null).find('[role="alert"]').exists()).toBe(false);
  });
});
