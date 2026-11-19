import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import TicketDetailDialog from '../TicketDetailDialog.vue';

const currentRole = ref('administrator');

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn(), getters: {} }),
  useMapGetter: key => {
    if (key === 'getCurrentRole') return currentRole;
    if (key === 'tickets/getUIFlags') return ref({});
    return ref(1);
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const OPEN_IN_CLICKUP = 'MEUS_TICKETS.DETAIL.OPEN_IN_CLICKUP';

const mountWith = async ticket => {
  const wrapper = mount(TicketDetailDialog, {
    global: {
      stubs: {
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  wrapper.vm.openWith({ display_id: 7, sync_status: 'synced', ...ticket });
  await wrapper.vm.$nextTick();
  return wrapper;
};

const clickupButton = wrapper =>
  wrapper.findAll('button').find(b => b.text() === OPEN_IN_CLICKUP);

describe('TicketDetailDialog ClickUp button', () => {
  beforeEach(() => {
    currentRole.value = 'administrator';
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  afterEach(() => vi.restoreAllMocks());

  it('opens the ticket task URL in a new tab', async () => {
    const wrapper = await mountWith({
      clickup_task_id: 'abc123',
      clickup_task_url: 'https://app.clickup.com/t/abc123',
    });

    await clickupButton(wrapper).trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      'https://app.clickup.com/t/abc123',
      '_blank'
    );
  });

  it('builds the URL from the task id when the ticket has no URL', async () => {
    const wrapper = await mountWith({ clickup_task_id: 'abc123' });

    await clickupButton(wrapper).trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      'https://app.clickup.com/t/90132001451/abc123',
      '_blank'
    );
  });

  it('hides the button for non-administrators', async () => {
    currentRole.value = 'manager';
    const wrapper = await mountWith({ clickup_task_id: 'abc123' });

    expect(clickupButton(wrapper)).toBeUndefined();
  });
});
