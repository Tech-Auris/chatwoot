<script setup>
import { computed, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { offersLossReasonCondition } from 'dashboard/helper/automationHelper';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// The CSAT survey rule as conditions on the conversation, the same way the
// automation rules are built: labels, funnel stage and — once a condition
// picks Perdido — the loss reason, joined by E / OU.
const conditions = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();
const { operators } = useOperators();

const labels = useMapGetter('labels/getLabels');
const funnelStages = useMapGetter('funnelStages/getFunnelStages');
const lossReasons = useMapGetter('lossReasons/getLossReasons');

const stageDot = color =>
  h('span', {
    class: 'rounded-full',
    style: { backgroundColor: color, height: '6px', width: '6px' },
  });

const filterType = (key, label, options, operatorKeys) => ({
  attributeKey: key,
  value: key,
  attributeName: label,
  label,
  inputType: 'multiSelect',
  options,
  filterOperators: operatorKeys.map(op => operators.value[op]),
  dataType: 'text',
  attributeModel: 'standard',
});

const filterTypes = computed(() => {
  const types = [
    filterType(
      'labels',
      t('INBOX_MGMT.CSAT.SURVEY_RULE.ATTRIBUTES.LABELS'),
      (labels.value || []).map(({ title }) => ({ id: title, name: title })),
      ['contains', 'does_not_contain']
    ),
  ];
  // Accounts without the funnel get no stages, so no funnel conditions.
  if (funnelStages.value?.length) {
    types.push(
      filterType(
        'funnel_stage_id',
        t('INBOX_MGMT.CSAT.SURVEY_RULE.ATTRIBUTES.FUNNEL_STAGE'),
        funnelStages.value.map(({ id, name, color }) => ({
          id,
          name,
          icon: stageDot(color),
        })),
        ['equal_to', 'not_equal_to']
      )
    );
  }
  if (offersLossReasonCondition(conditions.value, funnelStages.value)) {
    types.push(
      filterType(
        'loss_reason_id',
        t('INBOX_MGMT.CSAT.SURVEY_RULE.ATTRIBUTES.LOSS_REASON'),
        (lossReasons.value || []).map(({ id, name }) => ({ id, name })),
        ['equal_to', 'not_equal_to']
      )
    );
  }
  return types;
});

const addCondition = () => {
  conditions.value = [
    ...conditions.value,
    {
      attribute_key: 'labels',
      filter_operator: 'contains',
      values: [],
      query_operator: 'and',
    },
  ];
};

const removeCondition = index => {
  conditions.value = conditions.value.filter((_, i) => i !== index);
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <ul
      v-if="conditions.length"
      class="grid gap-4 list-none p-3 mb-0 outline outline-1 rounded-xl -outline-offset-1 outline-n-weak dark:outline-n-strong"
    >
      <template v-for="(condition, i) in conditions" :key="i">
        <ConditionRow
          v-if="i === 0"
          v-model:attribute-key="condition.attribute_key"
          v-model:filter-operator="condition.filter_operator"
          v-model:values="condition.values"
          :filter-types="filterTypes"
          :show-query-operator="false"
          @remove="removeCondition(i)"
        />
        <ConditionRow
          v-else
          v-model:attribute-key="condition.attribute_key"
          v-model:filter-operator="condition.filter_operator"
          v-model:query-operator="conditions[i - 1].query_operator"
          v-model:values="condition.values"
          :filter-types="filterTypes"
          show-query-operator
          @remove="removeCondition(i)"
        />
      </template>
    </ul>
    <div>
      <NextButton
        icon="i-lucide-plus"
        blue
        faded
        sm
        :label="t('INBOX_MGMT.CSAT.SURVEY_RULE.ADD_CONDITION')"
        @click="addCondition"
      />
    </div>
  </div>
</template>
