import { HOME_SECTIONS, useHomeSections } from '../useHomeSections';

const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

describe('useHomeSections', () => {
  it('asks for every section with the filters and merges the cards', async () => {
    const fetchSection = vi.fn(({ name }) =>
      Promise.resolve({ data: { buckets: [], [`${name}_card`]: 1 } })
    );
    const { metrics, sectionStatus, loadSections } =
      useHomeSections(fetchSection);

    await loadSections({ since: 1, until: 2 });

    expect(fetchSection).toHaveBeenCalledTimes(HOME_SECTIONS.length);
    expect(fetchSection).toHaveBeenCalledWith({
      name: 'leads',
      since: 1,
      until: 2,
    });
    expect(metrics.value).toMatchObject({ leads_card: 1, ai_card: 1 });
    expect(sectionStatus('funnel')).toEqual({
      ready: true,
      loading: false,
      error: false,
    });
  });

  it('shows each section as soon as it arrives', async () => {
    const slow = deferred();
    const { sectionStatus, loadSection } = useHomeSections(({ name }) =>
      name === 'funnel' ? slow.promise : Promise.resolve({ data: { n: 1 } })
    );

    const funnel = loadSection('funnel', {});
    await loadSection('leads', {});

    expect(sectionStatus('leads').ready).toBe(true);
    expect(sectionStatus('funnel')).toMatchObject({
      ready: false,
      loading: true,
    });

    slow.resolve({ data: { n: 2 } });
    await funnel;
    expect(sectionStatus('funnel').ready).toBe(true);
  });

  it('keeps the answer of the last request when an older one arrives later', async () => {
    const older = deferred();
    const newer = deferred();
    const fetchSection = vi
      .fn()
      .mockReturnValueOnce(older.promise)
      .mockReturnValueOnce(newer.promise);
    const { sections, sectionStatus, loadSection } =
      useHomeSections(fetchSection);

    const first = loadSection('leads', { period: 'month' });
    const second = loadSection('leads', { period: 'today' });
    newer.resolve({ data: { period: 'today' } });
    await second;
    older.resolve({ data: { period: 'month' } });
    await first;

    expect(sections.value.leads.data).toEqual({ period: 'today' });
    expect(sectionStatus('leads').loading).toBe(false);
  });

  it('shows the error only in the section that failed', async () => {
    const { sectionStatus, loadSections } = useHomeSections(({ name }) =>
      name === 'ai'
        ? Promise.reject(new Error('timeout'))
        : Promise.resolve({ data: {} })
    );

    await loadSections({});

    expect(sectionStatus('ai')).toEqual({
      ready: false,
      loading: false,
      error: true,
    });
    expect(sectionStatus('leads').error).toBe(false);
  });

  it('keeps the numbers when the silent refresh fails', async () => {
    const fetchSection = vi
      .fn()
      .mockResolvedValueOnce({ data: { total: 3 } })
      .mockRejectedValueOnce(new Error('timeout'));
    const { sections, sectionStatus, loadSection } =
      useHomeSections(fetchSection);

    await loadSection('leads', {});
    await loadSection('leads', {}, { silent: true });

    expect(sections.value.leads.data).toEqual({ total: 3 });
    expect(sectionStatus('leads').error).toBe(false);
  });

  it('does not refresh silently a section still loading', async () => {
    const pending = deferred();
    const fetchSection = vi.fn().mockReturnValue(pending.promise);
    const { loadSection } = useHomeSections(fetchSection);

    loadSection('leads', {});
    await loadSection('leads', {}, { silent: true });

    expect(fetchSection).toHaveBeenCalledTimes(1);
  });
});
