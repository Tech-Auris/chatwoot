import { mount } from '@vue/test-utils';
import ContactOptOutWarning from '../ContactOptOutWarning.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, params) => `${key} ${JSON.stringify(params)}` }),
}));

const mountWarning = contact =>
  mount(ContactOptOutWarning, { props: { contact } });

describe('ContactOptOutWarning', () => {
  it('warns about a contact picked from the search with a marketing opt-out', () => {
    const text = mountWarning({
      id: 7,
      marketingOptOut: true,
      marketingOptOutAt: 1792684800,
      marketingOptOutSource: 'meta',
    }).text();

    expect(text).toContain('FORM.MARKETING_OPT_OUT_WARNING');
    expect(text).toContain('MARKETING_OPT_OUT.ON_SINCE');
    expect(text).toContain('MARKETING_OPT_OUT.SOURCE.META');
  });

  it('warns when the window was opened from the contact itself', () => {
    const wrapper = mountWarning({
      id: 7,
      marketing_opt_out: true,
      marketing_opt_out_source: 'template_button',
    });

    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('SOURCE.TEMPLATE_BUTTON');
  });

  it('shows nothing for a contact without opt-out or without a contact', () => {
    expect(
      mountWarning({ id: 7, marketingOptOut: false })
        .find('[role="alert"]')
        .exists()
    ).toBe(false);
    expect(mountWarning(null).find('[role="alert"]').exists()).toBe(false);
  });

  it('follows the selected contact when it changes', async () => {
    const wrapper = mountWarning({ id: 7, marketingOptOut: true });
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);

    await wrapper.setProps({ contact: { id: 8, marketingOptOut: false } });

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
});
