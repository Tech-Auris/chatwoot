import { mount, flushPromises } from '@vue/test-utils';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappNumberWarning from '../WhatsappNumberWarning.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: { checkWhatsappNumber: vi.fn() },
}));

const baileysInbox = {
  id: 3,
  channelType: 'Channel::Whatsapp',
  provider: 'baileys',
};

const mountWarning = async (props = {}) => {
  const wrapper = mount(WhatsappNumberWarning, {
    props: {
      targetInbox: baileysInbox,
      selectedContact: { id: 7, phoneNumber: '+5531998010696' },
      ...props,
    },
  });
  await flushPromises();
  return wrapper;
};

const hasAlert = wrapper => wrapper.find('[role="alert"]').exists();

describe('WhatsappNumberWarning', () => {
  beforeEach(() => {
    InboxesAPI.checkWhatsappNumber.mockReset();
  });

  it('warns when the inbox answers that the number has no WhatsApp', async () => {
    InboxesAPI.checkWhatsappNumber.mockResolvedValue({
      data: { exists: false },
    });

    const wrapper = await mountWarning();

    expect(InboxesAPI.checkWhatsappNumber).toHaveBeenCalledWith(
      3,
      '+5531998010696'
    );
    expect(hasAlert(wrapper)).toBe(true);
    expect(wrapper.text()).toContain(
      'COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_NUMBER_MISSING'
    );
  });

  it('reads the phone of a contact opened from its own page', async () => {
    InboxesAPI.checkWhatsappNumber.mockResolvedValue({
      data: { exists: false },
    });

    const wrapper = await mountWarning({
      selectedContact: { id: 7, phone_number: '+5531998010696' },
    });

    expect(hasAlert(wrapper)).toBe(true);
  });

  it('shows nothing when the number has WhatsApp', async () => {
    InboxesAPI.checkWhatsappNumber.mockResolvedValue({
      data: { exists: true, phone: '553198010696' },
    });

    expect(hasAlert(await mountWarning())).toBe(false);
  });

  it('shows nothing when nobody could answer', async () => {
    InboxesAPI.checkWhatsappNumber.mockResolvedValue({ data: {} });
    expect(hasAlert(await mountWarning())).toBe(false);

    InboxesAPI.checkWhatsappNumber.mockRejectedValue(new Error('timeout'));
    expect(hasAlert(await mountWarning())).toBe(false);
  });

  it('does not ask for inboxes other than Baileys', async () => {
    const wrapper = await mountWarning({
      targetInbox: {
        id: 4,
        channelType: 'Channel::Whatsapp',
        provider: 'whatsapp_cloud',
      },
    });

    expect(InboxesAPI.checkWhatsappNumber).not.toHaveBeenCalled();
    expect(hasAlert(wrapper)).toBe(false);
  });

  it('drops the warning when the inbox changes', async () => {
    InboxesAPI.checkWhatsappNumber.mockResolvedValue({
      data: { exists: false },
    });
    const wrapper = await mountWarning();
    expect(hasAlert(wrapper)).toBe(true);

    await wrapper.setProps({
      targetInbox: { id: 9, channelType: 'Channel::Email' },
    });
    await flushPromises();

    expect(hasAlert(wrapper)).toBe(false);
  });
});
