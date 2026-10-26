import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import AiOffSchedule from '../AiOffSchedule.vue';
import InboxAiScheduleAPI from 'dashboard/api/inboxAiSchedule';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref([{ id: 4, name: 'Recepção' }]),
}));
vi.mock('dashboard/api/inboxAiSchedule', () => ({
  default: { show: vi.fn(), update: vi.fn() },
}));

describe('AI off schedule', () => {
  beforeEach(() => {
    InboxAiScheduleAPI.show.mockResolvedValue({
      data: {
        enabled: true,
        team_id: 4,
        timezone: 'America/Sao_Paulo',
        hours: [{ day_of_week: 1, from: '08:00', to: '12:00' }],
      },
    });
    InboxAiScheduleAPI.update.mockResolvedValue({ data: {} });
  });

  const mountSchedule = () =>
    mount(AiOffSchedule, {
      props: { inbox: { id: 7 } },
      global: {
        stubs: {
          SettingsToggleSection: true,
          SettingsFieldSection: true,
          Select: true,
          NextButton: true,
        },
        directives: { tooltip: {} },
      },
    });

  it('saves every range of every day with the team', async () => {
    const wrapper = mountSchedule();
    await flushPromises();
    const { setupState } = wrapper.vm.$;
    setupState.addRange(1);
    setupState.state.days[1][1] = { from: '13:00', to: '18:00' };

    await setupState.save();

    expect(InboxAiScheduleAPI.update).toHaveBeenCalledWith(7, {
      enabled: true,
      teamId: 4,
      hours: [
        { day_of_week: 1, from: '08:00', to: '12:00' },
        { day_of_week: 1, from: '13:00', to: '18:00' },
      ],
    });
  });

  it('blocks saving a range that ends before it starts', async () => {
    const wrapper = mountSchedule();
    await flushPromises();
    const { setupState } = wrapper.vm.$;
    setupState.state.days[1][0] = { from: '12:00', to: '08:00' };

    expect(setupState.hasError).toBe(true);
  });
});
