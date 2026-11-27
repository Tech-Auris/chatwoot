import { shallowMount, flushPromises } from '@vue/test-utils';
import WhatsappLinkDeviceModal from '../WhatsappLinkDeviceModal.vue';

const KEY = 'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL';
const USE_PAIRING_CODE_KEY = `${KEY}.USE_PAIRING_CODE`;
const USE_QRCODE_KEY = `${KEY}.USE_QRCODE`;
const LOADING_PAIRING_CODE_KEY = `${KEY}.LOADING_PAIRING_CODE`;
const PAIRING_CODE_HELP_KEY = `${KEY}.PAIRING_CODE_HELP`;

const dispatch = vi.fn(() => Promise.resolve());
const role = { isAdmin: true, isManager: false };

vi.mock('vuex', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
}));

vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return {
    useAdmin: () => ({
      isAdmin: computed(() => role.isAdmin),
      isManager: computed(() => role.isManager),
    }),
  };
});

const connecting = {
  connection: 'connecting',
  qr_data_url: 'data:image/png;base64,x',
};

const mountModal = ({
  provider = 'baileys',
  providerConnection = connecting,
} = {}) =>
  shallowMount(WhatsappLinkDeviceModal, {
    props: {
      show: true,
      onClose: () => {},
      inbox: {
        id: 1,
        name: 'WhatsApp',
        provider,
        provider_connection: providerConnection,
      },
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'woot-modal': { template: '<div><slot /></div>' },
        'router-link': true,
        Button: {
          props: ['label'],
          template: '<button>{{ label }}<slot /></button>',
        },
      },
    },
  });

const pairingCodeButton = wrapper =>
  wrapper.findAll('button').find(b => b.text() === USE_PAIRING_CODE_KEY);

beforeEach(() => {
  dispatch.mockClear();
  role.isAdmin = true;
  role.isManager = false;
});

describe('WhatsappLinkDeviceModal pairing by code', () => {
  it('is offered next to the QR on a Baileys inbox', () => {
    const wrapper = mountModal();

    expect(wrapper.html()).toContain('data:image/png;base64,x');
    expect(wrapper.html()).toContain(USE_PAIRING_CODE_KEY);
  });

  it('is offered to managers too', () => {
    role.isAdmin = false;
    role.isManager = true;

    expect(mountModal().html()).toContain(USE_PAIRING_CODE_KEY);
  });

  it('is not offered to agents', () => {
    role.isAdmin = false;

    expect(mountModal().html()).not.toContain(USE_PAIRING_CODE_KEY);
  });

  it('is not offered on other providers', () => {
    expect(mountModal({ provider: 'zapi' }).html()).not.toContain(
      USE_PAIRING_CODE_KEY
    );
  });

  // The QR is still on the record until the code arrives: leaving it up would put the
  // operator back on the thing they just said they could not use.
  it('waits for the code instead of falling back to the QR', async () => {
    const wrapper = mountModal();

    await pairingCodeButton(wrapper).trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/requestPairingCode', 1);
    expect(wrapper.html()).toContain(LOADING_PAIRING_CODE_KEY);
    expect(wrapper.html()).not.toContain('data:image/png;base64,x');
  });

  it('shows the code with the instructions and the way back to the QR', async () => {
    const wrapper = mountModal({
      providerConnection: {
        connection: 'connecting',
        pairing_code: 'K7QP2M4X',
      },
    });

    await pairingCodeButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.html()).toContain('K7QP-2M4X');
    expect(wrapper.html()).toContain(PAIRING_CODE_HELP_KEY);
    expect(wrapper.html()).toContain(USE_QRCODE_KEY);
  });

  it('goes back to the QR by setting the channel up again', async () => {
    const wrapper = mountModal();
    await pairingCodeButton(wrapper).trigger('click');
    await flushPromises();
    dispatch.mockClear();

    await wrapper
      .findAll('button')
      .find(b => b.text() === USE_QRCODE_KEY)
      .trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/setupChannelProvider', 1);
    expect(wrapper.html()).toContain('data:image/png;base64,x');
  });
});
