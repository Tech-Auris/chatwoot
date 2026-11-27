import { describe, it, expect, beforeEach, vi } from 'vitest';
import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';
import ZapiWebhookToken from '../ZapiWebhookToken.vue';

vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return { ...actual, useI18n: () => ({ t: key => key }) };
});

const mockAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockAlert(...args),
}));

vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { rotateZapiWebhookToken: vi.fn() },
}));

const mountSection = () =>
  mount(ZapiWebhookToken, {
    props: { inbox: { id: 7 } },
    global: {
      stubs: {
        SettingsSection: defineComponent({
          name: 'SettingsSection',
          template: '<div><slot /></div>',
        }),
      },
    },
  });

const button = wrapper =>
  wrapper.find('[data-test-id="rotate-zapi-webhook-token"]');

describe('ZapiWebhookToken', () => {
  beforeEach(() => {
    mockAlert.mockReset();
    WhatsappChannel.rotateZapiWebhookToken.mockReset();
  });

  it('asks the server for a new address for this inbox', async () => {
    WhatsappChannel.rotateZapiWebhookToken.mockResolvedValue({});
    const wrapper = mountSection();

    await button(wrapper).trigger('click');
    await flushPromises();

    expect(WhatsappChannel.rotateZapiWebhookToken).toHaveBeenCalledWith(7);
    expect(mockAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.SUCCESS'
    );
  });

  it('tells the user when Z-API refuses', async () => {
    WhatsappChannel.rotateZapiWebhookToken.mockRejectedValue(new Error('422'));
    const wrapper = mountSection();

    await button(wrapper).trigger('click');
    await flushPromises();

    expect(mockAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.ERROR'
    );
  });
});
