import { mount, flushPromises } from '@vue/test-utils';
import AiDisabledToggle from '../AiDisabledToggle.vue';

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

const mountToggle = () => mount(AiDisabledToggle, { props: { contactId: 7 } });

describe('AiDisabledToggle', () => {
  beforeEach(() => {
    dispatch.mockReset();
  });

  it('is on by default, without an "off since" line', () => {
    contact = { id: 7, ai_disabled: false };

    const wrapper = mountToggle();

    expect(wrapper.find('[role="switch"]').attributes('aria-checked')).toBe(
      'true'
    );
    expect(wrapper.text()).not.toContain('AI_DISABLED.OFF_SINCE');
  });

  it('shows when it was turned off and by whom', () => {
    contact = {
      id: 7,
      ai_disabled: true,
      ai_disabled_at: 1794000000,
      ai_disabled_by_name: 'Ana',
    };

    const wrapper = mountToggle();

    expect(wrapper.find('[role="switch"]').attributes('aria-checked')).toBe(
      'false'
    );
    expect(wrapper.text()).toContain('AI_DISABLED.OFF_SINCE');
    expect(wrapper.text()).toContain('"user":"Ana"');
  });

  it('asks the API to turn the AI off when switched', async () => {
    contact = { id: 7, ai_disabled: false };
    const wrapper = mountToggle();

    await wrapper.find('[role="switch"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/setAiStatus', {
      id: 7,
      enabled: false,
    });
  });
});
