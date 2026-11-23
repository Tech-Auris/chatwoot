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

  describe("Clara's two faces (Atendimento and Assistente)", () => {
    const managerTeam = chat => ({
      visible: true,
      manages_team: true,
      members,
      chat_enabled: chat,
      chat_missing: chat ? null : 'openai_key',
    });
    const liveStatus = onDuty => ({
      secretary: onDuty
        ? { on_duty: true, active_conversations: 3, in_follow_up: 1 }
        : {
            on_duty: false,
            off_duty_reason: 'Sem pagamento',
            active_conversations: 0,
            in_follow_up: 0,
          },
      manager: { month: { leads: 40, appointments: 12, conversion_rate: 30 } },
    });

    it.each([
      [true, true, false],
      [true, false, false],
      [false, true, false],
      [false, false, true],
    ])('serving %s, assistant %s: faded %s', (onDuty, chat, faded) => {
      const clara = rows(mountPanel(managerTeam(chat), liveStatus(onDuty)))[0];
      const text = clara.text();

      expect(text).toContain('VIRTUAL_CLINIC.FACES.ATTENDANCE');
      expect(text).toContain(
        onDuty ? 'VIRTUAL_CLINIC.FACES.SERVING' : 'Sem pagamento'
      );
      expect(text).toContain('VIRTUAL_CLINIC.FACES.ASSISTANT');
      expect(text.includes('VIRTUAL_CLINIC.FACES.REASONS.MISSING_OPENAI')).toBe(
        !chat
      );
      expect(clara.classes().includes('opacity-50')).toBe(faded);
    });

    it('shows Helena only the assistant, with her month numbers, faded when it is off', () => {
      const helena = rows(mountPanel(managerTeam(false), liveStatus(true)))[1];

      expect(helena.text()).toContain('VIRTUAL_CLINIC.STATUS.MANAGER');
      expect(helena.text()).toContain('VIRTUAL_CLINIC.FACES.ASSISTANT');
      expect(helena.text()).not.toContain('VIRTUAL_CLINIC.FACES.ATTENDANCE');
      expect(helena.classes()).toContain('opacity-50');
    });

    it('says when no AI is serving the patients', () => {
      const clara = rows(
        mountPanel(managerTeam(true), {
          secretary: { on_duty: false, off_duty_reason: 'ai_not_found' },
        })
      )[0];

      expect(clara.text()).toContain(
        'VIRTUAL_CLINIC.FACES.REASONS.AI_NOT_FOUND'
      );
    });
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

  it("shows agents only Clara's attendance, without the manager numbers or the assistant", () => {
    const wrapper = mountPanel(
      { visible: true, chat_enabled: false, manages_team: false, members },
      { secretary: { on_duty: true, active_conversations: 3, in_follow_up: 1 } }
    );

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.FACES.ATTENDANCE');
    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.STATUS.MANAGER');
    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.FACES.ASSISTANT');
    expect(rows(wrapper)[1].classes()).not.toContain('opacity-50');
  });

  it('opens the manager without the chat, for her news', async () => {
    const wrapper = mountPanel({ visible: true, chat_enabled: false, members });

    await rows(wrapper)[0].trigger('click');
    await rows(wrapper)[1].trigger('click');

    expect(wrapper.emitted('selectMember')).toEqual([['manager']]);
  });

  it("opens the manager's summaries from the gear, for whoever manages the team", async () => {
    const wrapper = mountPanel({
      visible: true,
      chat_enabled: true,
      manages_team: true,
      members,
    });

    const gears = wrapper.findAll(
      'button[title="VIRTUAL_CLINIC.SUMMARY.OPEN"]'
    );
    expect(gears).toHaveLength(1);
    await gears[0].trigger('click');
    expect(wrapper.emitted('summarySettings')).toHaveLength(1);
  });
});
