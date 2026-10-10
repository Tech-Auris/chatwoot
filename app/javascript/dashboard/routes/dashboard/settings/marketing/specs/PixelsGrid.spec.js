import { mount, flushPromises } from '@vue/test-utils';
import PixelsGrid from '../PixelsGrid.vue';
import MarketingIntegrationsAPI from 'dashboard/api/marketingIntegrations';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/marketingIntegrations', () => ({
  default: {
    getPixels: vi.fn(),
    addPixel: vi.fn(),
    updatePixel: vi.fn(),
    removePixel: vi.fn(),
  },
}));

const mountGrid = props =>
  mount(PixelsGrid, {
    props: { resolveIntegrationId: vi.fn().mockResolvedValue(7), ...props },
    global: {
      stubs: {
        Icon: true,
        Button: {
          props: ['label', 'type'],
          emits: ['click'],
          template:
            '<button :type="type || \'button\'" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('PixelsGrid', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    MarketingIntegrationsAPI.getPixels.mockResolvedValue({
      data: {
        payload: [
          { id: 1, name: 'Principal', pixel_id: '111', status: 'active' },
          { id: 2, name: 'Agência', pixel_id: '222', status: 'test_mode' },
        ],
      },
    });
  });

  it('lists every pixel of the integration', async () => {
    const wrapper = mountGrid({ integrationId: 7 });
    await flushPromises();

    expect(MarketingIntegrationsAPI.getPixels).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain('Principal');
    expect(wrapper.text()).toContain('222');
  });

  it('creates the integration when the first pixel is added', async () => {
    const resolveIntegrationId = vi.fn().mockResolvedValue(9);
    const wrapper = mountGrid({ integrationId: null, resolveIntegrationId });
    await flushPromises();

    await wrapper.find('button').trigger('click');
    const inputs = wrapper.findAll('form input');
    await inputs[0].setValue('Principal');
    await inputs[1].setValue('333');
    await inputs[2].setValue('EAAG_token');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(resolveIntegrationId).toHaveBeenCalled();
    expect(MarketingIntegrationsAPI.addPixel).toHaveBeenCalledWith(
      9,
      expect.objectContaining({
        name: 'Principal',
        pixel_id: '333',
        access_token: 'EAAG_token',
        status: 'test_mode',
      })
    );
  });
});
