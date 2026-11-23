import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import MemberSettings from '../components/MemberSettings.vue';
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

const editor = { saveTeam: vi.fn(() => Promise.resolve()) };

const mountSettings = (persona, name) =>
  mount(MemberSettings, {
    props: { persona, name, editor },
    global: { stubs: { Dialog: DialogStub } },
  });

const confirm = async wrapper => {
  await wrapper.findComponent(DialogStub).vm.$emit('confirm');
  await flushPromises();
};

describe('MemberSettings', () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads the summaries the person wants and saves the new choice', async () => {
    const wrapper = mountSettings('manager', 'Helena');
    await flushPromises();
    const [daily, weekly, monthly] = wrapper.findAll('input[type="checkbox"]');
    expect(daily.element.checked).toBe(true);

    await weekly.setValue(true);
    await monthly.setValue(true);
    await wrapper.find('select').setValue('18');
    await confirm(wrapper);

    expect(VirtualClinicAPI.saveSummary).toHaveBeenCalledWith({
      daily: true,
      weekly: true,
      monthly: true,
      hour: 18,
    });
    expect(editor.saveTeam).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('renames the manager along with her summaries', async () => {
    const wrapper = mountSettings('manager', 'Helena');
    await flushPromises();

    await wrapper.find('input:not([type])').setValue('  Marta ');
    await confirm(wrapper);

    expect(editor.saveTeam).toHaveBeenCalledWith('manager', { name: 'Marta' });
    expect(VirtualClinicAPI.saveSummary).toHaveBeenCalled();
    expect(wrapper.emitted('renamed')).toHaveLength(1);
  });

  it('only has the name for the secretary', async () => {
    const wrapper = mountSettings('secretary', 'Clara');
    await flushPromises();

    expect(VirtualClinicAPI.getSummary).not.toHaveBeenCalled();
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);

    await wrapper.find('input').setValue('Bia');
    await confirm(wrapper);

    expect(editor.saveTeam).toHaveBeenCalledWith('secretary', { name: 'Bia' });
    expect(VirtualClinicAPI.saveSummary).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('goes back to the default name when left blank', async () => {
    const wrapper = mountSettings('secretary', 'Bia');

    await wrapper.find('input').setValue('');
    await confirm(wrapper);

    expect(editor.saveTeam).toHaveBeenCalledWith('secretary', {
      name: undefined,
    });
  });
});
