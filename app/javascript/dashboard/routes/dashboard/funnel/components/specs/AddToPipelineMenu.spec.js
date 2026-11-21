import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import PipelinesAPI from 'dashboard/api/pipelines';
import AddToPipelineMenu from '../AddToPipelineMenu.vue';

vi.mock('dashboard/api/pipelines', () => ({
  default: {
    contactEntries: vi.fn(),
    addContact: vi.fn(),
    removeEntry: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const openDialog = vi.fn();

const mountMenu = () => {
  const store = createStore({
    modules: {
      pipelines: {
        namespaced: true,
        getters: {
          getPipelines: () => [
            { id: 1, name: 'Protocolo Emagrecimento' },
            { id: 2, name: 'Retorno de consulta' },
          ],
        },
        actions: { get: vi.fn() },
      },
    },
  });
  return mount(AddToPipelineMenu, {
    props: { contactId: 7 },
    global: {
      plugins: [store],
      directives: { tooltip: {} },
      stubs: {
        Popover: {
          emits: ['show'],
          mounted() {
            this.$emit('show');
          },
          template: '<div><slot /><slot name="content" /></div>',
        },
        Dialog: {
          template: '<div />',
          methods: { open: openDialog, close: vi.fn() },
        },
      },
    },
  });
};

const rowFor = (wrapper, name) =>
  wrapper.findAll('button').find(button => button.text().includes(name));

describe('AddToPipelineMenu', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    PipelinesAPI.contactEntries.mockResolvedValue({
      data: { payload: [{ id: 50, pipeline_id: 1, closed_at: null }] },
    });
    PipelinesAPI.addContact.mockResolvedValue({});
  });

  it('checks the pipelines the contact is in progress in', async () => {
    const wrapper = mountMenu();
    await flushPromises();

    expect(
      rowFor(wrapper, 'Protocolo').find('.i-lucide-square-check').exists()
    ).toBe(true);
    expect(rowFor(wrapper, 'Retorno').find('.i-lucide-square').exists()).toBe(
      true
    );
  });

  it('adds the contact when an unchecked pipeline is clicked', async () => {
    const wrapper = mountMenu();
    await flushPromises();

    await rowFor(wrapper, 'Retorno').trigger('click');
    await flushPromises();

    expect(PipelinesAPI.addContact).toHaveBeenCalledWith(2, 7);
    expect(wrapper.emitted('changed')).toEqual([[2]]);
  });

  it('asks before taking the contact out of a pipeline', async () => {
    const wrapper = mountMenu();
    await flushPromises();

    await rowFor(wrapper, 'Protocolo').trigger('click');

    expect(openDialog).toHaveBeenCalled();
    expect(PipelinesAPI.removeEntry).not.toHaveBeenCalled();
  });

  it('filters the pipelines by name', async () => {
    const wrapper = mountMenu();
    await flushPromises();

    await wrapper.find('input[type="search"]').setValue('retorno');

    expect(rowFor(wrapper, 'Protocolo')).toBeUndefined();
    expect(rowFor(wrapper, 'Retorno')).toBeDefined();
  });
});
