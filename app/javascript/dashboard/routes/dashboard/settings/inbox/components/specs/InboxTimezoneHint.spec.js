import { mount } from '@vue/test-utils';
import InboxTimezoneHint from '../InboxTimezoneHint.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${params.timezone}` : key),
  }),
}));

describe('Inbox timezone hint', () => {
  const mountHint = timezone =>
    mount(InboxTimezoneHint, {
      props: { timezone, text: 'Ranges per day.' },
      global: { stubs: { NextButton: { template: '<button />' } } },
    });

  it('shows the readable name of the inbox timezone after the text', () => {
    const text = mountHint('America/Sao_Paulo').text();

    expect(text).toContain('Ranges per day.');
    expect(text).toContain('INBOX_MGMT.TIMEZONE.CURRENT Brasilia (GMT-03:00)');
  });

  it('asks to open the settings tab when changing it', async () => {
    const wrapper = mountHint('UTC');

    await wrapper.find('button').trigger('click');

    expect(wrapper.emitted('change')).toHaveLength(1);
  });
});
