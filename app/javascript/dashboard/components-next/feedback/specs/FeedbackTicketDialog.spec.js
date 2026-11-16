import { mount } from '@vue/test-utils';
import FeedbackTicketDialog from '../FeedbackTicketDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn(), getters: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountDialog = () =>
  mount(FeedbackTicketDialog, {
    global: {
      stubs: {
        Dialog: { template: '<div><slot /></div>' },
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });

const submitButton = wrapper =>
  wrapper
    .findAll('button')
    .find(b => b.text() === 'CONVERSATION.FEEDBACK_TICKET.SUBMIT');

describe('FeedbackTicketDialog', () => {
  it('renders both text boxes with a 5000 character counter', () => {
    const wrapper = mountDialog();
    const textareas = wrapper.findAll('textarea');

    expect(textareas).toHaveLength(2);
    textareas.forEach(textarea =>
      expect(textarea.attributes('maxlength')).toBe('5000')
    );
    expect(wrapper.text().match(/0 \/ 5000/g)).toHaveLength(2);
  });

  it('enables submit only when both fields are filled', async () => {
    const wrapper = mountDialog();
    const [relatar, esperado] = wrapper.findAll('textarea');

    expect(submitButton(wrapper).attributes('disabled')).toBeDefined();

    await relatar.setValue('A IA respondeu errado');
    expect(submitButton(wrapper).attributes('disabled')).toBeDefined();

    await esperado.setValue('Deveria ter oferecido horário');
    expect(submitButton(wrapper).attributes('disabled')).toBeUndefined();
    expect(wrapper.text()).toContain('21 / 5000');
  });
});
