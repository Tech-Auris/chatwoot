<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

// "Mover no funil para": the funnel (the Agendamento or a clinic pipeline),
// a stage of that funnel and, when the stage asks for one (Perdido), the loss
// reason. Kept as `[stage, lossReason]`, saved as `[stage_id, loss_reason_id]`
// under `move_to_funnel_stage` (Agendamento) or `move_to_pipeline_stage`.
const props = defineProps({
  actionName: { type: String, required: true },
  // Stages of the Agendamento.
  stages: { type: Array, default: () => [] },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});

const emit = defineEmits(['change']);
const params = defineModel({ type: Array, default: () => [] });

const AGENDAMENTO = 'agendamento';

const { t } = useI18n();
const store = useStore();
const lossReasons = useMapGetter('lossReasons/getLossReasons');
const pipelines = useMapGetter('pipelines/getPipelines');

const lossReasonOptions = computed(() =>
  (lossReasons.value || []).map(({ id, name }) => ({ id, name }))
);

const funnelOfCurrentValue = () => {
  const stageId = params.value?.[0]?.id;
  if (props.actionName === 'move_to_pipeline_stage') {
    return (
      pipelines.value.find(pipeline =>
        pipeline.stages.some(stage => stage.id === stageId)
      )?.id || null
    );
  }
  return stageId ? AGENDAMENTO : null;
};

const selectedFunnel = ref(funnelOfCurrentValue());
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
  if (selectedFunnel.value === AGENDAMENTO) return props.stages;
  const pipeline = pipelines.value.find(p => p.id === selectedFunnel.value);
  return (pipeline?.stages || []).map(stage => ({
    id: stage.id,
    name: stage.name,
    requires_loss_reason: stage.kind === 'lost',
  }));
});

const funnel = computed({
  get: () =>
    funnelOptions.value.find(option => option.id === selectedFunnel.value) ||
    {},
  // Another funnel clears the stage.
  set: option => {
    selectedFunnel.value = option?.id ?? null;
    emit('change', {
      actionName:
        option?.id && option.id !== AGENDAMENTO
          ? 'move_to_pipeline_stage'
          : 'move_to_funnel_stage',
      params: [],
    });
  },
});

const stage = computed({
  get: () =>
    stageOptions.value.find(option => option.id === params.value?.[0]?.id) ||
    null,
  // A new stage starts without a reason; one that needs it asks again.
  set: value => {
    params.value = value?.id ? [value] : [];
  },
});

const lossReason = computed({
  get: () => params.value?.[1] || null,
  set: value => {
    params.value = value ? [stage.value, value] : [stage.value];
  },
});

const needsLossReason = computed(() => stage.value?.requires_loss_reason);

onMounted(() => store.dispatch('pipelines/get'));
</script>

<template>
  <SingleSelect
    v-model="funnel"
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
      v-model="stage"
      :options="stageOptions"
      :placeholder="t('PIPELINES.PICKER.STAGE')"
      :dropdown-max-height="dropdownMaxHeight"
    />
  </div>
  <SingleSelect
    v-if="needsLossReason"
    v-model="lossReason"
    :options="lossReasonOptions"
    :placeholder="t('AUTOMATION.ACTION.LOSS_REASON_PLACEHOLDER')"
    :dropdown-max-height="dropdownMaxHeight"
  />
</template>
