import { mount } from '@vue/test-utils';
import FollowUpBadge from '../FollowUpBadge.vue';
import { delayLabel } from '../followUpFormatters';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const open = vi.fn();

const mountBadge = followUp =>
  mount(FollowUpBadge, {
    props: {
      conversationId: 221,
      followUp: {
        step: 2,
        total: 3,
        delay_minutes: 2,
        created_at: 1791580000,
        ...followUp,
      },
    },
    global: {
      stubs: {
        FollowUpHistoryDialog: { template: '<div />', methods: { open } },
      },
    },
  });

describe('FollowUpBadge', () => {
  it.each([
    ['running', 'text-n-blue-11'],
    ['failed', 'text-n-ruby-11'],
    ['ended', 'text-n-amber-11'],
  ])('colors the %s state', (state, color) => {
    const wrapper = mountBadge({ state });

    expect(wrapper.find('[role="button"]').classes()).toContain(color);
    expect(wrapper.text()).toContain('2');
  });

  it('opens the FUP history on click', async () => {
    await mountBadge({ state: 'running' })
      .find('[role="button"]')
      .trigger('click');

    expect(open).toHaveBeenCalled();
  });
});

describe('delayLabel', () => {
  it('reads minutes, hours and days', () => {
    expect(delayLabel(10)).toBe('10min');
    expect(delayLabel(150)).toBe('2h30min');
    expect(delayLabel(1800)).toBe('1d 6h');
  });
});
