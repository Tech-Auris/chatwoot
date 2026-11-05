import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import FunnelConversion from '../FunnelConversion.vue';
import ReportLoadError from '../ReportLoadError.vue';

const timeoutError = message => ({ response: { data: { error: message } } });

const buildStore = ({ funnel, campaigns }) => {
  const report = {
    stages: [{ id: 1, key: 'Lead', name: 'Lead', count: 3 }],
    kpis: { schedulingRate: 50 },
    lossReasons: [],
  };
  const fetchFunnel = vi.fn(funnel);
  const fetchCampaigns = vi.fn(campaigns);

  const store = createStore({
    modules: {
      summaryReports: {
        namespaced: true,
        getters: {
          getUIFlags: () => ({}),
          getFunnelConversionReport: () => report,
          getFunnelConversionCampaigns: () => [{ sourceId: 'FB-1' }],
        },
        actions: {
          fetchFunnelConversionReports: fetchFunnel,
          fetchFunnelConversionCampaigns: fetchCampaigns,
        },
      },
      inboxes: { namespaced: true, getters: { getInboxes: () => [] } },
      labels: { namespaced: true, getters: { getLabels: () => [] } },
    },
  });

  return { store, fetchFunnel, fetchCampaigns };
};

const mountComponent = store =>
  mount(FunnelConversion, {
    global: {
      plugins: [store],
      stubs: {
        WootDatePicker: true,
        FunnelChart: true,
        LossReasonsDonut: true,
        CampaignBreakdownTable: true,
        FunnelDrilldownDialog: true,
        Spinner: true,
      },
    },
  });

describe('FunnelConversion', () => {
  it('loads the funnel and the campaigns on separate requests', async () => {
    const { store, fetchFunnel, fetchCampaigns } = buildStore({
      funnel: () => Promise.resolve(),
      campaigns: () => Promise.resolve(),
    });
    const wrapper = mountComponent(store);
    await flushPromises();

    expect(fetchFunnel).toHaveBeenCalledTimes(1);
    expect(fetchCampaigns).toHaveBeenCalledTimes(1);
    expect(wrapper.findComponent({ name: 'FunnelChart' }).exists()).toBe(true);
    expect(wrapper.findComponent(ReportLoadError).exists()).toBe(false);
  });

  it('keeps the campaigns visible and offers a retry when the funnel fails', async () => {
    const { store, fetchFunnel } = buildStore({
      funnel: () => Promise.reject(timeoutError('Report took too long')),
      campaigns: () => Promise.resolve(),
    });
    const wrapper = mountComponent(store);
    await flushPromises();

    const error = wrapper.findComponent(ReportLoadError);
    expect(error.props('message')).toBe('Report took too long');
    expect(wrapper.findComponent({ name: 'FunnelChart' }).exists()).toBe(false);
    expect(
      wrapper.findComponent({ name: 'CampaignBreakdownTable' }).exists()
    ).toBe(true);
    // A failed load never shows the numbers of the previous filters.
    expect(wrapper.text()).not.toContain('50.0%');

    error.vm.$emit('retry');
    await flushPromises();
    expect(fetchFunnel).toHaveBeenCalledTimes(2);
  });

  it('keeps the funnel visible when only the campaigns fail', async () => {
    const { store } = buildStore({
      funnel: () => Promise.resolve(),
      campaigns: () => Promise.reject(new Error('network')),
    });
    const wrapper = mountComponent(store);
    await flushPromises();

    expect(wrapper.findComponent({ name: 'FunnelChart' }).exists()).toBe(true);
    expect(
      wrapper.findComponent({ name: 'CampaignBreakdownTable' }).exists()
    ).toBe(false);
    expect(wrapper.findComponent(ReportLoadError).props('message')).toBe(
      'Could not load this data.'
    );
  });
});
