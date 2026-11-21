import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import FunnelStagePicker from '../FunnelStagePicker.vue';

const SingleSelectStub = {
  props: ['modelValue', 'options'],
  emits: ['update:modelValue'],
  template: '<div class="single-select" />',
};

const mountPicker = ({
  attributeKey = 'funnel_stage_id',
  values = [],
} = {}) => {
  const store = createStore({
    modules: {
      funnelStages: {
        namespaced: true,
        getters: {
          getFunnelStages: () => [{ id: 1, name: 'Agendado', color: '#000' }],
        },
        actions: { get: vi.fn() },
      },
      pipelines: {
        namespaced: true,
        getters: {
          getPipelines: () => [
            {
              id: 9,
              name: 'Protocolo Emagrecimento',
              stages: [
                { id: 30, name: 'Retorno D+30', color: '#111', kind: 'open' },
              ],
            },
          ],
        },
        actions: { get: vi.fn() },
      },
    },
  });
  return mount(FunnelStagePicker, {
    props: {
      attributeKey,
      values,
      multiple: true,
    },
    global: { plugins: [store], stubs: { SingleSelect: SingleSelectStub } },
  });
};

const selects = wrapper => wrapper.findAllComponents(SingleSelectStub);

describe('FunnelStagePicker', () => {
  it('keeps the stage locked until a funnel is chosen', () => {
    const wrapper = mountPicker();

    expect(selects(wrapper)[0].props('modelValue')).toEqual({});
    expect(wrapper.find('.pointer-events-none').exists()).toBe(true);
  });

  it('opens a rule of the Agendamento with the Agendamento chosen', () => {
    const wrapper = mountPicker({ values: [{ id: 1, name: 'Agendado' }] });

    expect(selects(wrapper)[0].props('modelValue').id).toBe('agendamento');
    expect(selects(wrapper)[1].props('modelValue').id).toBe(1);
  });

  it('opens a rule of a clinic pipeline with its pipeline chosen', () => {
    const wrapper = mountPicker({
      attributeKey: 'pipeline_stage_id',
      values: [{ id: 30 }],
    });

    expect(selects(wrapper)[0].props('modelValue').id).toBe(9);
    expect(
      selects(wrapper)[1]
        .props('options')
        .map(o => o.id)
    ).toEqual([30]);
  });

  it('saves a clinic pipeline under pipeline_stage_id and clears the stage', async () => {
    const wrapper = mountPicker({ values: [{ id: 1, name: 'Agendado' }] });

    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 9 });

    expect(wrapper.emitted('update:attributeKey')).toEqual([
      ['pipeline_stage_id'],
    ]);
    expect(wrapper.emitted('update:values')).toEqual([[[]]]);
  });
});
