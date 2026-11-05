import { mount } from '@vue/test-utils';
import BaileysHistoryImportStatus from '../BaileysHistoryImportStatus.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vuex', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));

describe('History import status', () => {
  const mountStatus = historyImport =>
    mount(BaileysHistoryImportStatus, {
      props: {
        inbox: { provider_connection: { history_import: historyImport } },
      },
      global: { stubs: { Spinner: true } },
    });

  it('stays hidden until the first history batch arrives', () => {
    expect(mountStatus(undefined).text()).toBe('');
  });

  it('shows how many messages were imported once completed', () => {
    const text = mountStatus({
      status: 'completed',
      messages_imported: 120,
      finished_at: new Date().toISOString(),
    }).text();

    expect(text).toContain('BAILEYS_HISTORY_IMPORT.STATUS_COMPLETED');
    expect(text).toContain('BAILEYS_HISTORY_IMPORT.MESSAGES');
  });

  it('explains that the business did not share its history', () => {
    const text = mountStatus({ status: 'declined' }).text();

    expect(text).toContain('BAILEYS_HISTORY_IMPORT.STATUS_DECLINED');
    expect(text).toContain('BAILEYS_HISTORY_IMPORT.DECLINED');
    expect(text).not.toContain('BAILEYS_HISTORY_IMPORT.MESSAGES');
  });
});
