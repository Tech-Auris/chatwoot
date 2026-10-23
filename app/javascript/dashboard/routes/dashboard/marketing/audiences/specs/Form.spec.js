import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import Form from '../Form.vue';
import AudiencesAPI from 'dashboard/api/audiences';

const push = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: {} }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref([]),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/audiences', () => ({
  default: { preview: vi.fn(), create: vi.fn(), show: vi.fn() },
}));

const mountForm = () =>
  mount(Form, {
    global: {
      stubs: {
        AudienceConditionRow: { template: '<div class="condition" />' },
        RadioCard: true,
        Input: true,
        Spinner: true,
      },
    },
  });

describe('Audience form', () => {
  beforeEach(() => {
    AudiencesAPI.preview.mockResolvedValue({ data: { contacts_count: 7 } });
    AudiencesAPI.create.mockResolvedValue({
      data: { payload: { id: 9, ignored_conditions: [] } },
    });
  });

  it('joins the rule with AND, the exclusion with OR, and drops empty conditions', async () => {
    const wrapper = mountForm();
    const { setupState } = wrapper.vm.$;
    setupState.state.name = 'Qualificação · ABC';
    setupState.state.rule = [
      {
        attribute_key: 'funnel_stage_id',
        filter_operator: 'equal_to',
        values: [3],
      },
      { attribute_key: 'labels', filter_operator: 'equal_to', values: ['abc'] },
      { attribute_key: 'labels', filter_operator: 'equal_to', values: [] },
    ];
    setupState.state.exclusion = [
      { attribute_key: 'labels', filter_operator: 'equal_to', values: ['x'] },
      {
        attribute_key: 'status',
        filter_operator: 'equal_to',
        values: ['resolved'],
      },
    ];
    setupState.state.window = {
      type: 'last_days',
      days: '30',
      from: '',
      to: '',
    };

    await setupState.save();
    await flushPromises();

    expect(AudiencesAPI.create).toHaveBeenCalledWith({
      name: 'Qualificação · ABC',
      kind: 'dynamic',
      rule: [
        {
          attribute_key: 'funnel_stage_id',
          filter_operator: 'equal_to',
          values: [3],
          query_operator: 'AND',
        },
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['abc'],
          query_operator: null,
        },
      ],
      exclusion: [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['x'],
          query_operator: 'OR',
        },
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['resolved'],
          query_operator: null,
        },
      ],
      window: { type: 'last_days', days: 30 },
    });
    expect(push).toHaveBeenCalledWith({
      name: 'marketing_audiences_show',
      params: { audienceId: 9 },
    });
  });

  it('does not save without a name or with an incomplete window', () => {
    const { setupState } = mountForm().vm.$;
    expect(setupState.canSave).toBeFalsy();

    setupState.state.name = 'Público';
    setupState.state.window = { type: 'range', from: '2026-10-01', to: '' };

    expect(setupState.canSave).toBeFalsy();
  });
});
