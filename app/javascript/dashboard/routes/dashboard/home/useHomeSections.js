import { computed, ref } from 'vue';

// The cards of the Início page come a section at a time, all at once, so a
// slow section never holds back the others. Cards that read the same rows
// share a section.
export const HOME_SECTIONS = [
  'leads',
  'appointments',
  'follow_up',
  'outcomes',
  'funnel',
  'ai',
];

// `fetchSection({ name, ...filters })` answers like axios: `{ data }`.
export function useHomeSections(fetchSection) {
  const sections = ref(
    Object.fromEntries(
      HOME_SECTIONS.map(name => [
        name,
        { data: null, loading: false, error: false },
      ])
    )
  );

  // The last request of a section wins: a slow answer for the period picked
  // before never overwrites the one picked last. A silent load (the minute
  // refresh) shows no spinner, skips a section still loading and keeps the
  // numbers on a failure.
  const lastRequest = {};
  const loadSection = async (name, filters, { silent = false } = {}) => {
    const state = sections.value[name];
    if (silent && state.loading) return;
    lastRequest[name] = (lastRequest[name] || 0) + 1;
    const request = lastRequest[name];
    if (!silent) state.loading = true;
    let payload = null;
    try {
      ({ data: payload } = await fetchSection({ name, ...filters }));
    } catch {
      payload = null;
    }
    if (request !== lastRequest[name]) return;
    state.loading = false;
    if (payload) {
      state.data = payload;
      state.error = false;
    } else if (!silent) {
      state.data = null;
      state.error = true;
    }
  };

  const loadSections = (filters, options) =>
    Promise.all(HOME_SECTIONS.map(name => loadSection(name, filters, options)));

  const sectionStatus = name => {
    const { data, loading, error } = sections.value[name];
    return { ready: !!data, loading, error };
  };

  // Every card's numbers that arrived so far, by card.
  const metrics = computed(() =>
    Object.assign({}, ...HOME_SECTIONS.map(name => sections.value[name].data))
  );

  return { sections, metrics, loadSection, loadSections, sectionStatus };
}
