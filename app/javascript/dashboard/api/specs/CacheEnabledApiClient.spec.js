import inboxesAPI from '../inboxes';

describe('CacheEnabledApiClient', () => {
  const originalAxios = window.axios;
  const originalInitDb = inboxesAPI.dataManager.initDb;

  beforeEach(() => {
    vi.useFakeTimers();
    window.axios = { get: vi.fn(() => Promise.resolve({ data: {} })) };
  });

  afterEach(() => {
    vi.useRealTimers();
    window.axios = originalAxios;
    inboxesAPI.dataManager.initDb = originalInitDb;
  });

  // Another tab still holding the cache this tab's logout deleted used to
  // leave the inbox list loading forever.
  it('loads from the network when the cache never opens', async () => {
    inboxesAPI.dataManager.initDb = () => new Promise(() => {});

    const request = inboxesAPI.get(true);
    await vi.advanceTimersByTimeAsync(3000);
    await request;

    expect(window.axios.get).toHaveBeenCalledWith(inboxesAPI.url);
  });
});
