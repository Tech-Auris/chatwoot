import { ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import Index from '../Index.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { rememberInbox, rememberedInbox } from '../rememberedInbox';

const push = vi.fn();
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/metaTemplates', () => ({
  default: { fetch: vi.fn(), sync: vi.fn() },
}));

const inboxes = ref([]);
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: name =>
    name === 'getCurrentRole' ? ref('administrator') : inboxes,
}));

const cloudInbox = (id, name) => ({
  id,
  name,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
});

const mountIndex = () =>
  shallowMount(Index, {
    global: {
      stubs: {
        SettingsLayout: { template: '<div><slot name="body" /></div>' },
      },
    },
  });

describe('Meta templates Index', () => {
  beforeEach(() => {
    localStorage.clear();
    push.mockClear();
    MetaTemplatesAPI.fetch.mockReset();
    MetaTemplatesAPI.fetch.mockResolvedValue({
      data: {
        templates: [{ id: 1, name: 'oi', status: 'APPROVED' }],
        last_synced_at: '2026-11-16',
      },
    });
    inboxes.value = [cloudInbox(5, 'Aline'), cloudInbox(7, 'Carol')];
  });

  it('opens on the inbox remembered in the browser', async () => {
    rememberInbox('1', 7);
    mountIndex();
    await flushPromises();

    expect(MetaTemplatesAPI.fetch).toHaveBeenCalledWith({ inboxId: 7 });
  });

  it('falls back to the first inbox when the remembered one is gone', async () => {
    rememberInbox('1', 99);
    mountIndex();
    await flushPromises();

    expect(MetaTemplatesAPI.fetch).toHaveBeenCalledWith({ inboxId: 5 });
    expect(rememberedInbox('1')).toBe(5);
  });

  it('opens the new template form on the selected inbox', async () => {
    rememberInbox('1', 7);
    const wrapper = mountIndex();
    await flushPromises();

    const newButton = wrapper
      .findAllComponents(Button)
      .find(button => button.props('label') === 'META_TEMPLATES.NEW.CTA');
    await newButton.trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'meta_templates_new',
      query: { inbox_id: 7 },
    });
  });
});
