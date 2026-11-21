import { describe, it, expect, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import SummarySettings from '../components/SummarySettings.vue';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/virtualClinic', () => ({
  default: {
    getSummary: vi.fn(() =>
      Promise.resolve({
        data: { daily: true, weekly: false, monthly: false, hour: 8 },
      })
    ),
    saveSummary: vi.fn(() => Promise.resolve({ data: {} })),
  },
}));

const DialogStub = defineComponent({
  emits: ['close'],
  setup(_, { slots, emit, expose }) {
    expose({ open: () => {}, close: () => emit('close') });
    return () => h('div', slots.default?.());
  },
});

describe('SummarySettings', () => {
  it('loads the summaries the person wants and saves the new choice', async () => {
    const wrapper = mount(SummarySettings, {
      props: { name: 'Helena' },
      global: { stubs: { Dialog: DialogStub } },
    });
    await flushPromises();
    const [daily, weekly, monthly] = wrapper.findAll('input[type="checkbox"]');
    expect(daily.element.checked).toBe(true);

    await weekly.setValue(true);
    await monthly.setValue(true);
    await wrapper.find('select').setValue('18');
    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(VirtualClinicAPI.saveSummary).toHaveBeenCalledWith({
      daily: true,
      weekly: true,
      monthly: true,
      hour: 18,
    });
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
