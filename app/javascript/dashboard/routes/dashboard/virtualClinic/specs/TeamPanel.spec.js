import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import TeamPanel from '../components/TeamPanel.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push }),
}));

const dispatch = vi.fn(() => Promise.resolve({ id: 77 }));
const agents = [
  { id: 3, name: 'Juliana Reis', availability_status: 'offline' },
  { id: 2, name: 'Marcos Silva', availability_status: 'online' },
  { id: 1, name: 'Dra. Paula', availability_status: 'online' },
];
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => ({
    value: key === 'getCurrentUserID' ? 1 : agents,
  }),
}));

const members = [
  { persona: 'secretary', name: 'Clara' },
  { persona: 'manager', name: 'Helena' },
];

const mountPanel = (aiTeam, status = null) =>
  mount(TeamPanel, {
    props: { clinicName: 'Clínica Sorriso', aiTeam, status },
    global: { stubs: { 'router-link': { template: '<a><slot /></a>' } } },
  });

describe('TeamPanel', () => {
  it('lets the user pick a member when the AI team is on', async () => {
    const wrapper = mountPanel({ visible: true, enabled: true, members });

    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('selectMember')).toEqual([['manager']]);
  });

  it('shows what each teammate is doing from the live status', () => {
    const wrapper = mountPanel(
      { visible: true, enabled: true, members },
      {
        secretary: { active_conversations: 7, in_follow_up: 4 },
        manager: {
          month: { leads: 412, appointments: 131, conversion_rate: 31.8 },
        },
      }
    );

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.STATUS.SECRETARY');
    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.STATUS.MANAGER');
  });

  it('points to the OpenAI key when it is missing and blocks selection', async () => {
    const wrapper = mountPanel({
      visible: true,
      enabled: false,
      missing: 'openai_key',
      members,
    });

    await wrapper.findAll('button')[0].trigger('click');

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.AI_TEAM.CONFIGURE_OPENAI');
    expect(wrapper.emitted('selectMember')).toBeUndefined();
  });

  it('hides the AI team from users who cannot see it', () => {
    const wrapper = mountPanel({ visible: false, enabled: false, members: [] });

    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.AI_TEAM.TITLE');
  });

  it('lists the user first, then online people, and opens a DM on click', async () => {
    const wrapper = mountPanel({ visible: false, members: [] });
    const names = wrapper.findAll('button').map(b => b.text());

    expect(names[0]).toContain('Dra. Paula');
    expect(names[1]).toContain('Marcos Silva');

    await wrapper.findAll('button')[1].trigger('click');
    await Promise.resolve();

    expect(dispatch).toHaveBeenCalledWith('internalChat/create', {
      channel: { channel_type: 'dm' },
      member_ids: [2],
    });
    expect(push).toHaveBeenCalledWith({
      name: 'internal_chat_dm',
      params: { accountId: '1', channelId: 77 },
    });
  });
});
