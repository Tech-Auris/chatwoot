import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import DailyQuestionLimitCard from '../components/DailyQuestionLimitCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const account = { value: { virtual_clinic_enabled: true } };
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: account }),
}));
vi.mock('dashboard/api/virtualClinic', () => ({
  default: { getConfig: vi.fn(), updateSettings: vi.fn() },
}));

const mountCard = () =>
  mount(DailyQuestionLimitCard, {
    global: {
      stubs: { Button: { template: '<button @click="$attrs.onClick" />' } },
    },
  });

describe('DailyQuestionLimitCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    account.value = { virtual_clinic_enabled: true };
  });

  it('lets the administrator save the daily limit', async () => {
    VirtualClinicAPI.getConfig.mockResolvedValue({
      data: {
        ai_team: { can_manage_settings: true, daily_question_limit: 60 },
      },
    });
    VirtualClinicAPI.updateSettings.mockResolvedValue({});
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('input').element.value).toBe('60');
    await wrapper.find('input').setValue('100');
    await wrapper.find('button').trigger('click');

    expect(VirtualClinicAPI.updateSettings).toHaveBeenCalledWith({
      daily_question_limit: 100,
    });
  });

  it('stays hidden for accounts without the Clínica virtual', async () => {
    account.value = { virtual_clinic_enabled: false };
    const wrapper = mountCard();
    await flushPromises();

    expect(VirtualClinicAPI.getConfig).not.toHaveBeenCalled();
    expect(wrapper.find('section').exists()).toBe(false);
  });

  it('stays hidden from managers', async () => {
    VirtualClinicAPI.getConfig.mockResolvedValue({
      data: {
        ai_team: { can_manage_settings: false, daily_question_limit: 60 },
      },
    });
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('section').exists()).toBe(false);
  });
});
