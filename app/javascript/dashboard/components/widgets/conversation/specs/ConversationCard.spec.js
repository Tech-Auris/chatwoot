import { mount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const LONG_AGENT = 'Flaviana Margareth | Diagnostico & Especialidades';

const mountCard = (props = {}) =>
  mount(ConversationCard, {
    props: {
      chat: { id: 1, priority: 'high', ai_enabled: true, messages: [] },
      currentContact: { name: 'Maria Souza' },
      inbox: { id: 2, name: 'Clinica Diagnóstico Avançado Unidade Centro' },
      showInboxName: true,
      showAssignee: true,
      ...props,
    },
    global: {
      stubs: {
        Avatar: { props: ['name'], template: '<span class="avatar" />' },
        AiStatusBadge: { template: '<span class="ai-badge" />' },
        CardPriorityIcon: true,
        MessagePreview: true,
        CardLabels: true,
        SLACardLabel: true,
        VoiceCallStatus: true,
        TimeAgo: true,
        UnreadBadge: true,
        Checkbox: true,
        Icon: true,
        FluentIcon: true,
      },
      mocks: { $t: (key, params) => `${key} ${JSON.stringify(params)}` },
    },
  });

describe('ConversationCard header', () => {
  it('shows the assignee as an avatar, never as text, and keeps the AI badge', () => {
    const wrapper = mountCard({ assignee: { id: 3, name: LONG_AGENT } });

    const assignee = wrapper.find('[data-test-id="card-assignee"]');
    expect(assignee.exists()).toBe(true);
    expect(wrapper.text()).not.toContain(LONG_AGENT);
    expect(wrapper.find('.ai-badge').exists()).toBe(true);
  });

  it('shows only the inbox, the priority and the AI badge without an assignee', () => {
    const wrapper = mountCard({ assignee: {} });

    expect(wrapper.find('[data-test-id="card-assignee"]').exists()).toBe(false);
    expect(wrapper.find('.ai-badge').exists()).toBe(true);
  });
});
