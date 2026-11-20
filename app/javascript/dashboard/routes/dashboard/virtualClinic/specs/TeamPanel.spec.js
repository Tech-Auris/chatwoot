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
  {
    id: 10,
    name: 'IA | Auris',
    availability_status: 'online',
    is_ai_user: true,
  },
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

// The buttons of the list, after the "edit your avatar" one of the header.
const rows = wrapper => wrapper.findAll('button').slice(1);

describe('TeamPanel', () => {
  it('lets the user pick a member when the AI team is on', async () => {
    const wrapper = mountPanel({ visible: true, chat_enabled: true, members });

    await rows(wrapper)[1].trigger('click');

    expect(wrapper.emitted('selectMember')).toEqual([['manager']]);
  });

  it('shows what each teammate is doing from the live status', () => {
    const wrapper = mountPanel(
      { visible: true, chat_enabled: true, members },
      {
        secretary: { on_duty: true, active_conversations: 7, in_follow_up: 4 },
        manager: {
          month: { leads: 412, appointments: 131, conversion_rate: 31.8 },
        },
      }
    );

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.STATUS.SECRETARY');
    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.STATUS.MANAGER');
  });

  it('keeps Clara serving patients without the OpenAI key, only the chat is off', () => {
    const wrapper = mountPanel(
      {
        visible: true,
        chat_enabled: false,
        chat_missing: 'openai_key',
        members,
      },
      {
        secretary: { on_duty: true, active_conversations: 3, in_follow_up: 1 },
        manager: {
          month: { leads: 40, appointments: 12, conversion_rate: 30 },
        },
      }
    );
    const clara = rows(wrapper)[0];

    expect(clara.text()).toContain('VIRTUAL_CLINIC.STATUS.SECRETARY');
    expect(clara.text()).toContain('VIRTUAL_CLINIC.AI_TEAM.CHAT_OFF');
    expect(clara.classes()).not.toContain('opacity-50');
  });

  it('fades Clara only when she is not serving patients', () => {
    const wrapper = mountPanel(
      { visible: true, chat_enabled: true, members },
      {
        secretary: {
          on_duty: false,
          off_duty_reason: 'Sem pagamento',
          active_conversations: 0,
          in_follow_up: 0,
        },
        manager: {
          month: { leads: 40, appointments: 12, conversion_rate: 30 },
        },
      }
    );

    expect(rows(wrapper)[0].classes()).toContain('opacity-50');
    expect(rows(wrapper)[0].text()).toContain('VIRTUAL_CLINIC.STATUS.OFF_DUTY');
    expect(rows(wrapper)[1].classes()).not.toContain('opacity-50');
  });

  it('points to the OpenAI key when it is missing and blocks selection', async () => {
    const wrapper = mountPanel({
      visible: true,
      chat_enabled: false,
      chat_missing: 'openai_key',
      members,
    });

    await rows(wrapper)[0].trigger('click');

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.AI_TEAM.CONFIGURE_OPENAI');
    expect(wrapper.emitted('selectMember')).toBeUndefined();
  });

  it('hides the AI team from users who cannot see it', () => {
    const wrapper = mountPanel({
      visible: false,
      chat_enabled: false,
      members: [],
    });

    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.AI_TEAM.TITLE');
  });

  it('lists the user first, then online people, and opens a DM on click', async () => {
    const wrapper = mountPanel({ visible: false, members: [] });
    const names = rows(wrapper).map(b => b.text());

    expect(names[0]).toContain('Dra. Paula');
    expect(names[1]).toContain('Marcos Silva');
    expect(names.join()).not.toContain('IA | Auris');

    await rows(wrapper)[1].trigger('click');
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

  it('opens the avatar editor from the header and from your own row', async () => {
    const wrapper = mountPanel({ visible: false, members: [] });

    await wrapper.findAll('button')[0].trigger('click');
    await rows(wrapper)[0].trigger('click');

    expect(wrapper.emitted('editAvatar')).toHaveLength(2);
    expect(dispatch).not.toHaveBeenCalledWith(
      'internalChat/create',
      expect.anything()
    );
  });
});
