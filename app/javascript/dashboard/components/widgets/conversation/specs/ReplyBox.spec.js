import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import ReplyBox from '../ReplyBox.vue';

const CHAT = {
  id: 1,
  inbox_id: 1,
  can_reply: true,
  status: 'open',
  meta: { sender: { id: 2 } },
  messages: [],
};

const buildStore = ({ inbox, chat }) =>
  createStore({
    state: { chat: { ...CHAT, ...chat }, drafts: {} },
    mutations: {
      selectChat: (s, c) => {
        s.chat = c;
      },
    },
    actions: {
      'draftMessages/setReplyEditorMode': () => {},
      'draftMessages/set': () => {},
      'draftMessages/delete': () => {},
      'conversationTypingStatus/toggleTyping': () => {},
    },
    getters: {
      getSelectedChat: s => s.chat,
      getCurrentUser: () => ({ id: 7, name: 'Agent', accounts: [] }),
      getCurrentAccountId: () => 1,
      getMessageSignature: () => '',
      getUISettings: () => ({}),
      getLastEmailInSelectedChat: () => null,
      'globalConfig/get': () => ({}),
      'inboxes/getInbox': () => id => ({ id, ...inbox }),
      'inboxes/getWhatsAppTemplates': () => () => [],
      'contacts/getContact': () => () => ({}),
      'draftMessages/get': () => () => '',
      'draftMessages/getReplyEditorMode': () => REPLY_EDITOR_MODES.REPLY,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'accounts/getAccount': () => () => ({}),
      'portals/allPortals': () => [],
      'integrations/getUIFlags': () => ({ isFetching: false }),
    },
  });

// Every mount subscribes to the global reply-to bus in mounted(), so unmount
// them or a later emit reaches every surviving wrapper.
const mounted = [];
afterEach(() => {
  while (mounted.length) mounted.pop().unmount();
});

const mountWith = ({ inbox, chat } = {}) => {
  const store = buildStore({ inbox, chat });
  const wrapper = shallowMount(ReplyBox, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      stubs: {
        WootMessageEditor: {
          name: 'WootMessageEditor',
          template: '<div />',
          methods: { focusEditorInputField: () => {} },
        },
      },
    },
  });
  mounted.push(wrapper);
  return { wrapper, store };
};

const WHATSAPP = { channel_type: 'Channel::Whatsapp' };
const switchTo = async (wrapper, mode) => {
  wrapper.vm.setReplyMode(mode);
  await nextTick();
};
const stageImage = async wrapper => {
  wrapper.vm.stageFile({ name: 'current.png', file: new Blob(['image']) });
  await vi.waitUntil(() => wrapper.vm.attachedFiles.length > 0);
};

describe('ReplyBox voice note on a private note', () => {
  it('offers the recorder on a note and records it as MP3', async () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' },
    });
    expect(wrapper.vm.audioRecordFormat).toBe(AUDIO_FORMATS.OGG);

    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);

    expect(wrapper.vm.showAudioRecorder).toBe(true);
    expect(wrapper.vm.audioRecordFormat).toBe(AUDIO_FORMATS.MP3);
  });

  it('unlocks the recorder on a note in an inbox that takes no uploads', async () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Tiktok' },
      chat: {
        additional_attributes: { tiktok_capabilities: { image_send: false } },
      },
    });
    expect(wrapper.vm.showAudioRecorder).toBe(false);

    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);

    expect(wrapper.vm.showAudioRecorder).toBe(true);
  });

  it('sends a recorded note as a private recorded audio', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });
    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);
    const file = new File(['audio'], 'nota.mp3', { type: 'audio/mpeg' });
    wrapper.vm.attachedFiles = [{ isRecordedAudio: true, resource: { file } }];

    const payload = wrapper.vm.getMessagePayload('');

    expect(payload.private).toBe(true);
    expect(payload.isRecordedAudio).toEqual(['nota.mp3']);
  });

  it('drops a staged recording when the agent switches to reply', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });
    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);
    wrapper.vm.attachedFiles = [
      { isRecordedAudio: true, resource: { file: new Blob(['audio']) } },
    ];
    wrapper.vm.isRecordingAudio = true;

    await switchTo(wrapper, REPLY_EDITOR_MODES.REPLY);

    expect(wrapper.vm.attachedFiles).toEqual([]);
    expect(wrapper.vm.isRecordingAudio).toBe(false);
  });

  it('drops a cited private note when the composer leaves note mode', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });
    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);
    wrapper.vm.inReplyTo = { id: 99, private: true };

    await switchTo(wrapper, REPLY_EDITOR_MODES.REPLY);

    expect(wrapper.vm.inReplyTo?.id).toBeUndefined();
  });

  it('drops an upload that lands after the agent switched to reply', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });
    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);

    wrapper.vm.stageFile({ isRecordedAudio: true, file: new Blob(['audio']) });
    await switchTo(wrapper, REPLY_EDITOR_MODES.REPLY);
    // Queued after the switch, so waiting for it makes the recording's absence
    // a result rather than a race.
    await stageImage(wrapper);

    expect(wrapper.vm.attachedFiles).toHaveLength(1);
    expect(wrapper.vm.attachedFiles[0].isRecordedAudio).toBe(false);
  });

  it('drops a recording whose conversion outlived the note it was made on', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });
    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);

    wrapper.vm.toggleAudioRecorder();
    await switchTo(wrapper, REPLY_EDITOR_MODES.REPLY);
    wrapper.vm.onFinishRecorder({
      name: 'nota.mp3',
      file: new Blob(['audio']),
    });
    await stageImage(wrapper);

    expect(wrapper.vm.attachedFiles).toHaveLength(1);
    expect(wrapper.vm.attachedFiles[0].isRecordedAudio).toBe(false);
  });

  it('drops an upload that lands after the agent changed conversation', async () => {
    const { wrapper, store } = mountWith({ inbox: WHATSAPP });
    await switchTo(wrapper, REPLY_EDITOR_MODES.NOTE);

    wrapper.vm.stageFile({ isRecordedAudio: true, file: new Blob(['audio']) });
    store.commit('selectChat', { ...CHAT, id: 2 });
    await nextTick();
    await stageImage(wrapper);

    expect(wrapper.vm.attachedFiles).toHaveLength(1);
    expect(wrapper.vm.attachedFiles[0].isRecordedAudio).toBe(false);
  });

  it('drops a capture still uploading when its message is sent', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });

    wrapper.vm.stageFile({ isRecordedAudio: true, file: new Blob(['audio']) });
    wrapper.vm.clearMessage();
    await stageImage(wrapper);

    expect(wrapper.vm.attachedFiles).toHaveLength(1);
    expect(wrapper.vm.attachedFiles[0].isRecordedAudio).toBe(false);
  });

  it('stages a file the uploader hands over with its (newFile, oldFile) pair', async () => {
    const { wrapper } = mountWith({ inbox: WHATSAPP });

    const newFile = { name: 'doc.pdf', file: new Blob(['pdf']) };
    const oldFile = { name: 'doc.pdf', file: new Blob(['pdf']), progress: '0' };
    wrapper.vm.stageFile(newFile, oldFile);
    await vi.waitUntil(() => wrapper.vm.attachedFiles.length > 0);

    expect(wrapper.vm.attachedFiles).toHaveLength(1);
  });
});
