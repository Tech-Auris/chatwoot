import { mount, flushPromises } from '@vue/test-utils';
import TemplateForm from '../TemplateForm.vue';
import { SYSTEM_LOCKED_FIELDS } from '../../kit';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/metaTemplates', () => ({ default: {} }));

const kitTemplate = {
  name: 'lembrete_24h',
  language: 'pt_BR',
  category: 'UTILITY',
  parameter_format: 'NAMED',
  components: [
    {
      type: 'BODY',
      text: 'Olá {{nome}}! Seu atendimento na Clínica Sorriso é amanhã. Selecione:',
      example: {
        body_text_named_params: [{ param_name: 'nome', example: 'Maria' }],
      },
    },
    {
      type: 'BUTTONS',
      buttons: [
        { type: 'QUICK_REPLY', text: 'Confirmar' },
        { type: 'QUICK_REPLY', text: 'Cancelar' },
      ],
    },
  ],
};

const mountForm = props =>
  mount(TemplateForm, {
    props: {
      inboxes: [{ id: 3, name: 'WhatsApp' }],
      initialTemplate: kitTemplate,
      initialInboxId: 3,
      ...props,
    },
    global: {
      stubs: { Button: true, Spinner: true, TemplatePreview: true },
    },
  });

const systemProps = {
  lockedFields: SYSTEM_LOCKED_FIELDS,
  allowedVariables: { nome: 'Maria', dia: '15/09/2026' },
};

describe('TemplateForm with a kit system template', () => {
  it('locks everything but the body', async () => {
    const wrapper = mountForm(systemProps);
    await flushPromises();

    const name = wrapper.find('input[type="text"]');
    expect(name.attributes('disabled')).toBeDefined();
    wrapper.findAll('select').forEach(select => {
      if (select.element.value !== '3') {
        expect(select.attributes('disabled')).toBeDefined();
      }
    });
    expect(wrapper.find('textarea').attributes('disabled')).toBeUndefined();
    expect(wrapper.text()).not.toContain('HEADER_TOGGLE');
    expect(wrapper.text()).not.toContain('REMOVE_BUTTON');
    expect(wrapper.vm.$.setupState.isValid).toBe(true);
  });

  it('inserts a shortcut variable with its sample', async () => {
    const wrapper = mountForm(systemProps);
    await flushPromises();
    const { setupState } = wrapper.vm.$;

    setupState.insertVariable('dia');
    await flushPromises();

    expect(setupState.bodyText).toContain('{{dia}}');
    expect(setupState.bodySamples.dia).toBe('15/09/2026');
    expect(setupState.isValid).toBe(true);
  });

  it('blocks a variable outside the list', async () => {
    const wrapper = mountForm(systemProps);
    await flushPromises();
    const { setupState } = wrapper.vm.$;

    setupState.bodyText = 'Olá {{nome}}, traga {{documento}}. Selecione:';
    setupState.bodySamples.documento = 'RG';
    await flushPromises();

    expect(setupState.disallowedVariables).toEqual(['documento']);
    expect(setupState.isValid).toBe(false);
    expect(wrapper.text()).toContain('VAR_NOT_ALLOWED');
  });

  it('blocks clinic data the kit could not fill', async () => {
    const wrapper = mountForm(systemProps);
    await flushPromises();
    const { setupState } = wrapper.vm.$;

    setupState.bodyText = 'Olá {{nome}}, venha à [endereço da clínica]. Ok?';
    await flushPromises();

    expect(setupState.isValid).toBe(false);
    expect(wrapper.text()).toContain('KIT_PLACEHOLDER');
  });
});

describe('TemplateForm with a suggested template', () => {
  it('leaves every field editable', async () => {
    const wrapper = mountForm({});
    await flushPromises();

    const name = wrapper.find('input[type="text"]');
    expect(name.attributes('disabled')).toBeUndefined();
    expect(wrapper.text()).toContain('HEADER_TOGGLE');
    expect(wrapper.vm.$.setupState.isValid).toBe(true);
  });
});
