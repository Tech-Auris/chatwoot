import { mount, flushPromises } from '@vue/test-utils';
import SaveAsAudienceDialog from '../components/SaveAsAudienceDialog.vue';
import AudiencesAPI from 'dashboard/api/audiences';

const push = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../useAudienceFields', () => ({
  useAudienceFields: () => ({
    describe: () => '',
    describeWindow: () => '',
    optionsFor: () => [{ value: 4, label: 'Preço' }],
  }),
}));
vi.mock('dashboard/api/audiences', () => ({
  default: { preview: vi.fn(), create: vi.fn() },
}));

const DialogStub = {
  template: '<div><slot /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};

const mountDialog = props =>
  mount(SaveAsAudienceDialog, {
    props,
    global: {
      stubs: { Dialog: DialogStub, Input: true, RadioCard: true, Select: true },
    },
  });

describe('Save as audience dialog', () => {
  beforeEach(() => {
    AudiencesAPI.preview.mockResolvedValue({ data: { contacts_count: 3 } });
    AudiencesAPI.create.mockResolvedValue({
      data: { payload: { id: 12, ignored_conditions: [] } },
    });
  });

  it('creates the audience from the rule and window on screen', async () => {
    const wrapper = mountDialog({
      rule: [
        {
          attribute_key: 'funnel_stage_id',
          filter_operator: 'equal_to',
          values: [5],
        },
      ],
      window: { type: 'range', from: '2026-10-01', to: '2026-10-21' },
      pickLossReason: true,
    });
    const { setupState } = wrapper.vm.$;
    setupState.open();
    setupState.state.name = 'Perdidos · outubro';
    setupState.state.kind = 'static';
    setupState.state.lossReasonId = 4;

    await setupState.save();
    await flushPromises();

    expect(AudiencesAPI.create).toHaveBeenCalledWith({
      name: 'Perdidos · outubro',
      kind: 'static',
      source: 'filter',
      rule: [
        {
          attribute_key: 'funnel_stage_id',
          filter_operator: 'equal_to',
          values: [5],
          query_operator: 'and',
        },
        {
          attribute_key: 'loss_reason_id',
          filter_operator: 'equal_to',
          values: [4],
          query_operator: null,
        },
      ],
      window: { type: 'range', from: '2026-10-01', to: '2026-10-21' },
    });
    expect(push).toHaveBeenCalledWith({
      name: 'marketing_audiences_show',
      params: { audienceId: 12 },
    });
  });

  it('keeps the conversation filter operators as they are', () => {
    const { setupState } = mountDialog({
      rule: [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['abc'],
          query_operator: 'or',
        },
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['open'],
          query_operator: 'and',
        },
      ],
    }).vm.$;

    expect(setupState.fullRule.map(c => c.query_operator)).toEqual([
      'or',
      null,
    ]);
  });
});
