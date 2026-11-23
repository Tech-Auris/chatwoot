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

  it('lists Luciano with his campaigns and cost per appointment', async () => {
    const team = [...members, { persona: 'marketing', name: 'Luciano' }];
    const wrapper = mountPanel(
      { visible: true, chat_enabled: true, members: team },
      {
        secretary: { on_duty: true, active_conversations: 0, in_follow_up: 0 },
        manager: {
          month: { leads: 412, appointments: 131, conversion_rate: 31.8 },
        },
        marketing: { active_campaigns: 6, cost_per_appointment: 85.4 },
      }
    );

    expect(wrapper.text()).toContain('Luciano');
    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.STATUS.MARKETING');
    await rows(wrapper)[2].trigger('click');
    expect(wrapper.emitted('selectMember')).toEqual([['marketing']]);
  });

  it('keeps Clara serving patients without the OpenAI key, only the chat is off', () => {
    const wrapper = mountPanel(
      {
        visible: true,
        chat_enabled: false,
        chat_missing: 'openai_key',
        manages_team: true,
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

  it('opens the profile editor from the header', async () => {
    const wrapper = mountPanel({ visible: false, members: [] });

    await wrapper.findAll('button')[0].trigger('click');

    expect(wrapper.emitted('editProfile')).toHaveLength(1);
  });

  it('lets whoever edits the clinic change the look of each AI teammate', async () => {
    const wrapper = mountPanel({
      visible: true,
      chat_enabled: true,
      can_edit_layout: true,
      members,
    });

    await wrapper
      .findAll('button[title="VIRTUAL_CLINIC.AVATAR.EDIT"]')[1]
      .trigger('click');

    expect(wrapper.emitted('editAvatar')).toEqual([['manager']]);
  });

  it('shows agents the team without the manager numbers or the chat-off hint', () => {
    const wrapper = mountPanel(
      { visible: true, chat_enabled: false, manages_team: false, members },
      { secretary: { on_duty: true, active_conversations: 3, in_follow_up: 1 } }
    );

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.STATUS.SECRETARY');
    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.STATUS.MANAGER');
    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.AI_TEAM.CHAT_OFF');
  });

  it('opens the manager without the chat, for her news', async () => {
    const wrapper = mountPanel({ visible: true, chat_enabled: false, members });

    await rows(wrapper)[0].trigger('click');
    await rows(wrapper)[1].trigger('click');

    expect(wrapper.emitted('selectMember')).toEqual([['manager']]);
  });

  it('opens the settings of each teammate from the gear, for whoever manages the team', async () => {
    const wrapper = mountPanel({
      visible: true,
      chat_enabled: true,
      manages_team: true,
      members,
    });

    const gears = wrapper.findAll(
      'button[title="VIRTUAL_CLINIC.MEMBER_SETTINGS.OPEN"]'
    );
    expect(gears).toHaveLength(2);
    await gears[0].trigger('click');
    await gears[1].trigger('click');
    expect(wrapper.emitted('memberSettings')).toEqual([
      ['secretary'],
      ['manager'],
    ]);
  });

  it('hides the gears from who does not manage the team', () => {
    const wrapper = mountPanel({ visible: true, chat_enabled: false, members });

    expect(
      wrapper.findAll('button[title="VIRTUAL_CLINIC.MEMBER_SETTINGS.OPEN"]')
    ).toHaveLength(0);
  });
});
