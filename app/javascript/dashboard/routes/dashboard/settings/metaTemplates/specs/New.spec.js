import { ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import New from '../New.vue';
import TemplateForm from '../components/TemplateForm.vue';
import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { rememberedInbox } from '../rememberedInbox';
import routes from '../metaTemplates.routes';

const push = vi.fn();
const route = { params: { accountId: '1' }, query: {} };
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => route,
  useRouter: () => ({ push }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/metaTemplates', () => ({
  default: { create: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref([{ id: 5 }]),
}));

const mountNew = () =>
  shallowMount(New, {
    global: {
      stubs: {
        SettingsLayout: { template: '<div><slot name="body" /></div>' },
      },
    },
  });

describe('Meta templates New', () => {
  beforeEach(() => {
    localStorage.clear();
    push.mockClear();
    route.query = {};
  });

  it('opens the form on the inbox passed by the list', () => {
    route.query = { inbox_id: '7' };
    const form = mountNew().findComponent(TemplateForm);

    expect(form.props('initialInboxId')).toBe(7);
  });

  it('returns to the list on the inbox the template was created in', async () => {
    MetaTemplatesAPI.create.mockResolvedValue({
      data: { templates: [], last_synced_at: null },
    });
    const form = mountNew().findComponent(TemplateForm);
    form.vm.$emit('submit', { inboxId: 9, template: { name: 'oi' } });
    await flushPromises();

    expect(rememberedInbox('1')).toBe(9);
    expect(push).toHaveBeenCalledWith({ name: 'meta_templates_index' });
  });

  it('mounts the form fresh on every visit so no draft comes back', () => {
    expect(routes.routes[0].props).toEqual({ keepAlive: false });
  });
});
