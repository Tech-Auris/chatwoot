<script setup>
import { computed, h, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import SingleSelect from './SingleSelect.vue';

// "Etapa do funil" as two required fields, in this order: the funnel (the
// Agendamento first, then the clinic pipelines, searchable) and a stage of
// that funnel. The Agendamento keeps writing `funnel_stage_id`; a clinic
// pipeline writes `pipeline_stage_id`, so rules and filters saved before
// keep working untouched.
const props = defineProps({
  // Automations keep the stage in an array, the conversation filter as one
  // option.
  multiple: { type: Boolean, default: false },
  dropdownMaxHeight: { type: String, default: 'max-h-64' },
});

const attributeKey = defineModel('attributeKey', {
  type: String,
  required: true,
});
const values = defineModel('values', {
  type: [Array, Object, String, Number],
  required: true,
});

const AGENDAMENTO = 'agendamento';

const { t } = useI18n();
const store = useStore();
const funnelStages = useMapGetter('funnelStages/getFunnelStages');
const pipelines = useMapGetter('pipelines/getPipelines');

const dot = color =>
  h('span', {
    class: 'rounded-full',
    style: { backgroundColor: color, height: '6px', width: '6px' },
  });

const toOption = stage => ({
  id: stage.id,
  name: stage.name,
  icon: dot(stage.color),
});

const selectedStageId = computed(() => {
  const value = Array.isArray(values.value) ? values.value[0] : values.value;
  return value?.id ?? null;
});

const funnelOfCurrentValue = () => {
  if (attributeKey.value === 'pipeline_stage_id') {
    return (
      pipelines.value.find(pipeline =>
        pipeline.stages.some(stage => stage.id === selectedStageId.value)
      )?.id || null
    );
  }
  return selectedStageId.value ? AGENDAMENTO : null;
};

const selectedFunnel = ref(funnelOfCurrentValue());
// A rule opened before the pipelines arrived finds its funnel once they do.
watch(pipelines, () => {
  if (!selectedFunnel.value) selectedFunnel.value = funnelOfCurrentValue();
});

const funnelOptions = computed(() => [
  { id: AGENDAMENTO, name: t('PIPELINES.AGENDAMENTO'), icon: 'i-lucide-lock' },
  ...pipelines.value.map(pipeline => ({
    id: pipeline.id,
    name: pipeline.name,
  })),
]);

const stageOptions = computed(() => {
  if (selectedFunnel.value === AGENDAMENTO)
    return funnelStages.value.map(toOption);
  const pipeline = pipelines.value.find(p => p.id === selectedFunnel.value);
  return (pipeline?.stages || []).map(stage => ({
    ...toOption(stage),
    kind: stage.kind,
  }));
});

const emptyValue = () => (props.multiple ? [] : {});

const funnelModel = computed({
  get: () =>
    funnelOptions.value.find(option => option.id === selectedFunnel.value) ||
    {},
  set: option => {
    selectedFunnel.value = option?.id ?? null;
    attributeKey.value =
      option?.id && option.id !== AGENDAMENTO
        ? 'pipeline_stage_id'
        : 'funnel_stage_id';
    values.value = emptyValue();
  },
});

const stageModel = computed({
  get: () =>
    stageOptions.value.find(option => option.id === selectedStageId.value) ||
    {},
  set: option => {
    if (!option?.id) {
      values.value = emptyValue();
      return;
    }
    values.value = props.multiple ? [option] : option;
  },
});

onMounted(() => {
  store.dispatch('funnelStages/get');
  store.dispatch('pipelines/get');
});
</script>

<template>
  <div class="flex items-center gap-2 min-w-0">
    <SingleSelect
      v-model="funnelModel"
      :options="funnelOptions"
      :placeholder="t('PIPELINES.PICKER.FUNNEL')"
      :dropdown-max-height="dropdownMaxHeight"
      disable-deselect
    />
    <div
      :class="{ 'pointer-events-none opacity-50': !selectedFunnel }"
      :title="selectedFunnel ? '' : t('PIPELINES.PICKER.FUNNEL_FIRST')"
    >
      <SingleSelect
        v-model="stageModel"
        :options="stageOptions"
        :placeholder="t('PIPELINES.PICKER.STAGE')"
        :dropdown-max-height="dropdownMaxHeight"
      />
    </div>
  </div>
</template>
