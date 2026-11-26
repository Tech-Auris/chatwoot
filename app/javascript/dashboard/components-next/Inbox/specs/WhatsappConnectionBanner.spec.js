import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import WhatsappConnectionBanner from '../WhatsappConnectionBanner.vue';

const KEY = 'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION';

const role = { isAdmin: ref(false), isManager: ref(false) };

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn(() => Promise.resolve()) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAdmin', () => ({ useAdmin: () => role }));

const stall = { consecutive_timeouts: 3, action: 'suppressed' };

const mountBanner = providerConnection =>
  mount(WhatsappConnectionBanner, {
    props: {
      inbox: {
        id: 1,
        provider: 'baileys',
        provider_connection: providerConnection,
      },
    },
    global: {
      stubs: {
        WhatsappLinkDeviceModal: true,
        Banner: {
          props: ['bannerMessage', 'hasActionButton'],
          template:
            '<div :data-action="String(hasActionButton)">{{ bannerMessage }}</div>',
        },
      },
    },
  });

describe('WhatsappConnectionBanner', () => {
  beforeEach(() => {
    role.isAdmin.value = false;
    role.isManager.value = false;
  });

  it('renders nothing while the number is connected and sending', () => {
    expect(mountBanner({ connection: 'open' }).html()).toBe('<!--v-if-->');
  });

  it('warns an admin that a connected number cannot send, with the action', () => {
    role.isAdmin.value = true;
    const banner = mountBanner({ connection: 'open', send_stall: stall });

    expect(banner.text()).toBe(`${KEY}.SEND_STALL`);
    expect(banner.find('[data-action]').attributes('data-action')).toBe('true');
  });

  it('tells an agent to contact the administrator, without an action', () => {
    const banner = mountBanner({ connection: 'open', send_stall: stall });

    expect(banner.text()).toBe(`${KEY}.SEND_STALL_CONTACT_ADMIN`);
    expect(banner.find('[data-action]').attributes('data-action')).toBe(
      'false'
    );
  });

  it('shows the offline banner when the stalled connection goes down', () => {
    const banner = mountBanner({ connection: 'close', send_stall: stall });

    expect(banner.text()).toBe(`${KEY}.NOT_CONNECTED_CONTACT_ADMIN`);
    expect(banner.find('[data-action]').attributes('data-action')).toBe('true');
  });
});
