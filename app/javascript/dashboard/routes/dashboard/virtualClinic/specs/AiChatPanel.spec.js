import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { emitter } from 'shared/helpers/mitt';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import AiChatPanel from '../components/AiChatPanel.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
    te: () => false,
  }),
}));
vi.mock('dashboard/api/virtualClinic', () => ({
  default: {
    getThread: vi.fn(),
    sendMessage: vi.fn(),
    resetThread: vi.fn(),
    getAlerts: vi.fn(),
    acknowledgeAlerts: vi.fn(),
  },
}));

const member = {
  persona: 'secretary',
  name: 'Clara',
  suggestions: ['Quem você está atendendo agora?'],
};

const mountPanel = (alertCount = 0, news = null) =>
  mount(AiChatPanel, {
    props: { member, alertCount, news },
    global: {
      stubs: { Button: true, Icon: true, ChatChart: true, HelenaNews: true },
      directives: {
        dompurifyHtml: (el, binding) => {
          el.innerHTML = binding.value;
        },
      },
    },
  });

describe('AiChatPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    VirtualClinicAPI.getThread.mockResolvedValue({ data: { messages: [] } });
  });

  it('sends a suggestion, shows the AI thinking and renders the answer when it arrives', async () => {
    VirtualClinicAPI.sendMessage.mockResolvedValue({
      data: {
        messages: [
          {
            id: 1,
            role: 'user',
            status: 'done',
            content: 'Quem você está atendendo agora?',
          },
          { id: 2, role: 'assistant', status: 'pending', content: null },
        ],
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.find('button.rounded-full').trigger('click');
    await flushPromises();

    expect(VirtualClinicAPI.sendMessage).toHaveBeenCalledWith(
      'secretary',
      'Quem você está atendendo agora?'
    );
    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.CHAT.THINKING');
    expect(wrapper.emitted('thinking').at(-1)).toEqual(['secretary']);

    emitter.emit('virtualClinicMessageUpdated', {
      id: 2,
      role: 'assistant',
      status: 'done',
      content: 'Agora estou com **7 pacientes**.',
      tool_calls: [{ name: 'atendimento_agora', arguments: {} }],
    });
    await flushPromises();

    expect(wrapper.html()).toContain('<strong>7 pacientes</strong>');
    expect(wrapper.text()).toContain('atendimento_agora');
    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.CHAT.THINKING');
  });

  it('explains the daily limit set by the clinic', async () => {
    VirtualClinicAPI.sendMessage.mockRejectedValue({
      response: { status: 429 },
    });
    const wrapper = mountPanel();
    await flushPromises();

    await wrapper.find('button.rounded-full').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.CHAT.DAILY_LIMIT');
  });

  it('shows what Clara raised her hand for, with the patients, and marks it as seen', async () => {
    VirtualClinicAPI.getAlerts.mockResolvedValue({
      data: {
        alerts: [
          {
            id: 7,
            persona: 'secretary',
            message: '1 paciente está sem resposta há mais de 30 minutos.',
            payload: {
              patients: [
                { name: 'Maria', conversation_id: 42, waiting_minutes: 51 },
              ],
            },
          },
          { id: 8, persona: 'manager', message: 'Faltas', payload: {} },
        ],
      },
    });
    const wrapper = mountPanel(1);
    await flushPromises();

    expect(wrapper.text()).toContain('1 paciente está sem resposta');
    expect(wrapper.text()).toContain('"name":"Maria","id":42,"minutes":51');
    expect(wrapper.text()).not.toContain('Faltas');
    expect(VirtualClinicAPI.acknowledgeAlerts).toHaveBeenCalledWith(
      'secretary'
    );
  });

  it('keeps the earlier talk above the alert and the new talk below it', async () => {
    VirtualClinicAPI.getThread.mockResolvedValue({
      data: {
        messages: [
          { id: 1, role: 'user', status: 'done', content: 'Pergunta antiga' },
        ],
      },
    });
    VirtualClinicAPI.getAlerts.mockResolvedValue({
      data: {
        alerts: [
          {
            id: 7,
            persona: 'secretary',
            message: '5 pacientes sem resposta',
            payload: {},
          },
        ],
      },
    });
    VirtualClinicAPI.sendMessage.mockResolvedValue({
      data: {
        messages: [
          { id: 2, role: 'user', status: 'done', content: 'Pergunta nova' },
          { id: 3, role: 'assistant', status: 'pending', content: null },
        ],
      },
    });
    const wrapper = mountPanel(1, { notifications: [], release: null });
    await flushPromises();

    await wrapper.find('button.rounded-full').trigger('click');
    await flushPromises();

    const html = wrapper.html();
    const order = [
      'Pergunta antiga',
      '5 pacientes sem resposta',
      'helena-news-stub',
      'Pergunta nova',
      'VIRTUAL_CLINIC.CHAT.THINKING',
    ].map(text => html.indexOf(text));
    expect(order.every(index => index > -1)).toBe(true);
    expect(order).toEqual([...order].sort((a, b) => a - b));
  });

  it('does not look for alerts when there are none', async () => {
    mountPanel();
    await flushPromises();
    expect(VirtualClinicAPI.getAlerts).not.toHaveBeenCalled();
  });

  it('shows the tool in use, then the text as it is written, then the chart', async () => {
    VirtualClinicAPI.getThread.mockResolvedValue({
      data: {
        messages: [
          { id: 1, role: 'user', status: 'done', content: 'Leads por mês?' },
          { id: 2, role: 'assistant', status: 'pending', content: null },
        ],
      },
    });
    const wrapper = mountPanel();
    await flushPromises();

    emitter.emit('virtualClinicMessageActivity', {
      id: 2,
      tool: 'funil_resumo',
    });
    await flushPromises();
    expect(wrapper.text()).toContain('VIRTUAL_CLINIC.CHAT.ACTIVITY');
    expect(wrapper.text()).toContain('"tool":"funil_resumo"');

    emitter.emit('virtualClinicMessageDelta', { id: 2, content: 'Em outubro' });
    await flushPromises();
    expect(wrapper.text()).toContain('Em outubro');
    expect(wrapper.text()).not.toContain('VIRTUAL_CLINIC.CHAT.ACTIVITY');

    emitter.emit('virtualClinicMessageUpdated', {
      id: 2,
      role: 'assistant',
      status: 'done',
      content: 'Em outubro foram 40 leads.',
      attachments: [
        { type: 'bar', title: 'Leads', labels: ['out'], series: [] },
      ],
    });
    await flushPromises();
    expect(wrapper.findAllComponents({ name: 'ChatChart' })).toHaveLength(1);
    expect(wrapper.text()).toContain('Em outubro foram 40 leads.');
  });
});
