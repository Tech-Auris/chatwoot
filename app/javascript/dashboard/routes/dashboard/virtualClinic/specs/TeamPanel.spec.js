import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import TeamPanel from '../components/TeamPanel.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const members = [
  { persona: 'secretary', name: 'Clara' },
  { persona: 'manager', name: 'Helena' },
];

const mountPanel = aiTeam =>
  mount(TeamPanel, {
    props: { clinicName: 'Clínica Sorriso', aiTeam },
    global: { stubs: { 'router-link': { template: '<a><slot /></a>' } } },
  });

describe('TeamPanel', () => {
  it('lets the user pick a member when the AI team is on', async () => {
    const wrapper = mountPanel({ visible: true, enabled: true, members });

    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('selectMember')).toEqual([['manager']]);
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
});
