<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

// "Mover no funil para": the stage and, when that stage asks for one
// (Perdido), the loss reason. Kept as `[stage, lossReason]`, which the rule
// saves as `[stage_id, loss_reason_id]`.
const props = defineProps({
  stages: {
    type: Array,
    default: () => [],
  },
  dropdownMaxHeight: {
    type: String,
    default: 'max-h-80',
  },
});

const params = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();
const lossReasons = useMapGetter('lossReasons/getLossReasons');

const lossReasonOptions = computed(() =>
  (lossReasons.value || []).map(({ id, name }) => ({ id, name }))
);

const stage = computed({
  get: () => params.value?.[0] || null,
  // A new stage starts without a reason; one that needs it asks again.
  set: value => {
    params.value = value ? [value] : [];
  },
});

const lossReason = computed({
  get: () => params.value?.[1] || null,
  set: value => {
    params.value = value ? [stage.value, value] : [stage.value];
  },
});

const needsLossReason = computed(
  () =>
    props.stages.find(option => option.id === stage.value?.id)
      ?.requires_loss_reason
);
</script>

<template>
  <SingleSelect
    v-model="stage"
    :options="stages"
    :dropdown-max-height="dropdownMaxHeight"
  />
  <SingleSelect
    v-if="needsLossReason"
    v-model="lossReason"
    :options="lossReasonOptions"
    :placeholder="t('AUTOMATION.ACTION.LOSS_REASON_PLACEHOLDER')"
    :dropdown-max-height="dropdownMaxHeight"
  />
</template>
