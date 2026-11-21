import { mount } from '@vue/test-utils';
import AutomationActionTemplateFallback from '../AutomationActionTemplateFallback.vue';

const templatesByInbox = { 5: [{ name: 'no_show', language: 'pt_BR' }] };

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getWhatsAppTemplates': id => templatesByInbox[id] || [],
    },
  }),
}));

const WhatsappTemplates = {
  name: 'WhatsappTemplates',
  props: ['inboxId'],
  emits: ['onSend', 'cancel', 'update:show'],
  template: '<div />',
};

const mountFallback = props =>
  mount(AutomationActionTemplateFallback, {
    props,
    global: {
      stubs: {
        WhatsappTemplates,
        TemplateQualityBadge: true,
        TemplateQualityWarning: true,
      },
    },
  });

describe('AutomationActionTemplateFallback', () => {
  it('asks for an inbox condition when the rule has none', () => {
    const wrapper = mountFallback({ conditions: [] });

    expect(wrapper.text()).toContain(
      'AUTOMATION.ACTION.TEMPLATE_FALLBACK.NEEDS_INBOX'
    );
    expect(wrapper.text()).not.toContain('AUTOMATION.ACTION.TEMPLATE_SELECT');
  });

  it('emits the picked template and its text', () => {
    const wrapper = mountFallback({
      conditions: [{ attribute_key: 'inbox_id', values: [{ id: 5 }] }],
    });
    const modal = wrapper.findComponent(WhatsappTemplates);
    const templateParams = { name: 'no_show', language: 'pt_BR' };

    expect(modal.props('inboxId')).toBe(5);
    modal.vm.$emit('onSend', { templateParams, message: 'Oi {{1}}' });

    expect(wrapper.emitted('update:modelValue')[0]).toEqual([
      templateParams,
      'Oi {{1}}',
    ]);
  });

  it('shows the chosen template', () => {
    const wrapper = mountFallback({
      modelValue: { name: 'no_show' },
      conditions: [{ attribute_key: 'inbox_id', values: 5 }],
    });

    expect(wrapper.text()).toContain('AUTOMATION.ACTION.TEMPLATE_SELECTED');
    expect(wrapper.text()).not.toContain(
      'AUTOMATION.ACTION.TEMPLATE_FALLBACK.NEEDS_INBOX'
    );
  });
});
