import { mount, flushPromises } from '@vue/test-utils';
import Reauthorize from '../Reauthorize.vue';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import { useAlert } from 'dashboard/composables';

const runEmbeddedSignup = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({ runEmbeddedSignup }),
}));
vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { postEmbeddedSignupAuthorization: vi.fn() },
}));
vi.mock('../utils', () => ({ setupFacebookSdk: vi.fn() }));

const inbox = {
  id: 418,
  provider_config: {
    business_account_id: 'old-waba',
    phone_number_id: 'old-number',
  },
};

const mountReauthorize = async () => {
  const wrapper = mount(Reauthorize, {
    props: { inbox },
    global: { stubs: { InboxReconnectionRequired: true } },
  });
  await flushPromises();
  return wrapper;
};

describe('WhatsApp reauthorize', () => {
  beforeEach(() => {
    window.chatwootConfig = {
      whatsappAppId: 'app',
      whatsappConfigurationId: 'config',
    };
    whatsappChannel.postEmbeddedSignupAuthorization.mockResolvedValue({
      data: { success: true },
    });
  });

  it('sends the WABA and number picked in the popup, not the stored ones', async () => {
    runEmbeddedSignup.mockResolvedValue({
      code: 'code',
      business_id: 'biz',
      waba_id: 'new-waba',
      phone_number_id: 'new-number',
    });
    const wrapper = await mountReauthorize();

    await wrapper.vm.requestAuthorization();

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).toHaveBeenCalledWith({
      inboxId: 418,
      code: 'code',
      business_id: 'biz',
      waba_id: 'new-waba',
      phone_number_id: 'new-number',
    });
  });

  it('keeps the stored number when the popup leaves it out for the same WABA', async () => {
    runEmbeddedSignup.mockResolvedValue({
      code: 'code',
      business_id: 'biz',
      waba_id: 'old-waba',
      phone_number_id: '',
    });
    const wrapper = await mountReauthorize();

    await wrapper.vm.requestAuthorization();

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        waba_id: 'old-waba',
        phone_number_id: 'old-number',
      })
    );
  });

  it('does not call the API when the popup is cancelled', async () => {
    whatsappChannel.postEmbeddedSignupAuthorization.mockClear();
    runEmbeddedSignup.mockResolvedValue(null);
    const wrapper = await mountReauthorize();

    await wrapper.vm.requestAuthorization();

    expect(
      whatsappChannel.postEmbeddedSignupAuthorization
    ).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'
    );
  });
});
