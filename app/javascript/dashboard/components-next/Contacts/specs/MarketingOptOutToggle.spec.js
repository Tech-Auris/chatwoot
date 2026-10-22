import { mount, flushPromises } from '@vue/test-utils';
import MarketingOptOutToggle from '../MarketingOptOutToggle.vue';

const dispatch = vi.fn();
let contact = {};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, params) => `${key} ${JSON.stringify(params)}` }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => ({ value: () => contact }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountToggle = () =>
  mount(MarketingOptOutToggle, { props: { contactId: 7 } });

describe('MarketingOptOutToggle', () => {
  beforeEach(() => {
    dispatch.mockReset();
  });

  it('explains what turning it on does while it is off', () => {
    contact = { id: 7, marketing_opt_out: false };

    const wrapper = mountToggle();

    expect(wrapper.find('[role="switch"]').attributes('aria-checked')).toBe(
      'false'
    );
    expect(wrapper.text()).toContain('MARKETING_OPT_OUT.OFF_HELP');
  });

  it('shows when it was turned on and by whom', () => {
    contact = {
      id: 7,
      marketing_opt_out: true,
      marketing_opt_out_at: 1792684800,
      marketing_opt_out_source: 'meta',
    };

    const wrapper = mountToggle();

    expect(wrapper.text()).toContain('MARKETING_OPT_OUT.ON_SINCE');
    expect(wrapper.text()).toContain('MARKETING_OPT_OUT.SOURCE.META');
  });

  it('asks the API to turn it on when switched', async () => {
    contact = { id: 7, marketing_opt_out: false };
    const wrapper = mountToggle();

    await wrapper.find('[role="switch"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/setMarketingOptOut', {
      id: 7,
      enabled: true,
    });
  });
});
