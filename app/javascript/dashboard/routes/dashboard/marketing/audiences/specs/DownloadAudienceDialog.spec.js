import { mount, flushPromises } from '@vue/test-utils';
import DownloadAudienceDialog from '../components/DownloadAudienceDialog.vue';
import AudiencesAPI from 'dashboard/api/audiences';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));
vi.mock('dashboard/api/audiences', () => ({
  default: { exportList: vi.fn() },
}));

const DialogStub = {
  template: '<div><slot /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};

describe('Download audience dialog', () => {
  it('downloads only the columns left checked', async () => {
    AudiencesAPI.exportList.mockResolvedValue({ data: 'csv' });
    const wrapper = mount(DownloadAudienceDialog, {
      props: { audience: { id: 3, name: 'Qualificação' } },
      global: { stubs: { Dialog: DialogStub, Checkbox: true } },
    });
    const { setupState } = wrapper.vm.$;
    Object.keys(setupState.picked).forEach(key => {
      setupState.picked[key] = ['name', 'phone_number'].includes(key);
    });

    await setupState.download();
    await flushPromises();

    expect(AudiencesAPI.exportList).toHaveBeenCalledWith(3, [
      'name',
      'phone_number',
    ]);
    expect(downloadCsvFile).toHaveBeenCalledWith('Qualificação.csv', 'csv');
    expect(wrapper.emitted('downloaded')).toHaveLength(1);
  });
});
