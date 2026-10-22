import { mount, flushPromises } from '@vue/test-utils';
import PreviousConversations from '../PreviousConversations.vue';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import MessageAPI from 'dashboard/api/inbox/message';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, ...args) => `${key} ${JSON.stringify(args)}` }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { getPrevious: vi.fn() },
}));
vi.mock('dashboard/api/inbox/message', () => ({
  default: { getMessagesAfter: vi.fn() },
}));

const conversation = (id, hasPrevious) => ({
  id,
  created_at: 1786000000,
  status: 'resolved',
  inbox_name: 'WhatsApp Clínica',
  messages_count: 2,
  has_previous: hasPrevious,
});

// #371 → #279 → #175, the first one of the contact in the inbox.
const previousOf = {
  371: conversation(279, true),
  279: conversation(175, false),
};

const mountChain = (oldestLoadedMessageId = 10) =>
  mount(PreviousConversations, {
    props: {
      conversationId: 371,
      contactName: 'Maria',
      currentUserId: 1,
      oldestLoadedMessageId,
    },
    global: {
      stubs: {
        MessageList: {
          name: 'MessageList',
          props: ['messages'],
          template: '<ul class="list" />',
        },
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

const openBanner = async wrapper => {
  await wrapper.find('button').trigger('click');
  await flushPromises();
  await flushPromises();
};

describe('PreviousConversations', () => {
  beforeEach(() => {
    ConversationAPI.getPrevious.mockImplementation(async id => ({
      data: { payload: previousOf[id] ?? null, first_message_id: 10 },
    }));
    MessageAPI.getMessagesAfter.mockResolvedValue({
      data: { payload: [{ id: 1 }, { id: 2 }] },
    });
  });

  it('offers the conversation right before the current one', async () => {
    const wrapper = mountChain();
    await flushPromises();

    expect(wrapper.find('button').text()).toContain('"id":279');
    expect(wrapper.findAll('section')).toHaveLength(0);
  });

  it('waits until the current conversation is loaded back to its first message', async () => {
    const wrapper = mountChain(50);
    await flushPromises();
    expect(wrapper.find('li').attributes('style')).toContain('display: none');

    await wrapper.setProps({ oldestLoadedMessageId: 10 });
    expect(wrapper.find('li').attributes('style') ?? '').not.toContain(
      'display: none'
    );
    expect(wrapper.find('button').text()).toContain('"id":279');
  });

  it('shows nothing when there is no previous conversation', async () => {
    ConversationAPI.getPrevious.mockResolvedValue({
      data: { payload: null, first_message_id: 10 },
    });
    const wrapper = mountChain();
    await flushPromises();

    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('opens one at a time, oldest on top, until the start of the history', async () => {
    const wrapper = mountChain();
    await flushPromises();

    await openBanner(wrapper);
    expect(MessageAPI.getMessagesAfter).toHaveBeenCalledWith({
      conversationId: 279,
      after: 0,
    });
    expect(wrapper.find('button').text()).toContain('"id":175');

    await openBanner(wrapper);
    const titles = wrapper.findAll('section header .font-semibold');
    expect(titles.map(title => title.text())).toEqual([
      expect.stringContaining('"id":175'),
      expect.stringContaining('"id":279'),
    ]);
    expect(wrapper.text()).toContain('HISTORY_START');
  });

  it('closing a conversation closes the older ones too', async () => {
    const wrapper = mountChain();
    await flushPromises();
    await openBanner(wrapper);
    await openBanner(wrapper);

    // #279 is the lower block; its Close button is the last one.
    const closeButtons = wrapper.findAll('section header button');
    await closeButtons[closeButtons.length - 1].trigger('click');

    expect(wrapper.findAll('section')).toHaveLength(0);
    expect(wrapper.find('button').text()).toContain('"id":279');
  });

  it('reads a long conversation whole, 100 messages at a time', async () => {
    const page = Array.from({ length: 100 }, (_, index) => ({ id: index + 1 }));
    MessageAPI.getMessagesAfter
      .mockResolvedValueOnce({ data: { payload: page } })
      .mockResolvedValueOnce({ data: { payload: [{ id: 101 }] } });
    const wrapper = mountChain();
    await flushPromises();
    await openBanner(wrapper);

    expect(MessageAPI.getMessagesAfter).toHaveBeenLastCalledWith({
      conversationId: 279,
      after: 100,
    });
    await vi.waitFor(() =>
      expect(wrapper.find('section ul.list').exists()).toBe(true)
    );
    expect(MessageAPI.getMessagesAfter).toHaveBeenCalledTimes(2);
  });
});
