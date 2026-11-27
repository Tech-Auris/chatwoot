<script setup>
import { computed, defineModel, h, watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import FilterSelect from './inputs/FilterSelect.vue';
import MultiSelect from './inputs/MultiSelect.vue';
import SingleSelect from './inputs/SingleSelect.vue';
import FunnelStagePicker from './inputs/FunnelStagePicker.vue';

import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { validateSingleFilter } from 'dashboard/helper/validations.js';

// filterTypes: import('vue').ComputedRef<FilterType[]>
const { filterTypes } = defineProps({
  showQueryOperator: { type: Boolean, default: false },
  filterTypes: { type: Array, required: true },
});

const emit = defineEmits(['remove']);
const { t } = useI18n();
const showErrors = ref(false);

const attributeKey = defineModel('attributeKey', {
  type: String,
  required: true,
});

const values = defineModel('values', {
  type: [String, Number, Array, Object],
  required: true,
});

const filterOperator = defineModel('filterOperator', {
  type: String,
  required: true,
});

const queryOperator = defineModel('queryOperator', {
  type: String,
  required: false,
  default: undefined,
  validator: value => ['and', 'or'].includes(value),
});

// A clinic pipeline stage is the same "Etapa do funil" attribute on screen;
// the funnel picked in FunnelStagePicker decides which key is saved.
const ATTRIBUTE_ALIASES = { pipeline_stage_id: 'funnel_stage_id' };
const displayAttributeKey = computed({
  get: () => ATTRIBUTE_ALIASES[attributeKey.value] || attributeKey.value,
  set: value => {
    attributeKey.value = value;
  },
});

const getFilterFromFilterTypes = key =>
  filterTypes.find(
    filterObj => filterObj.attributeKey === (ATTRIBUTE_ALIASES[key] || key)
  );

const currentFilter = computed(() =>
  getFilterFromFilterTypes(attributeKey.value)
);

const getOperator = (filter, selectedOperator) => {
  const operatorFromOptions = filter?.filterOperators?.find(
    operator => operator.value === selectedOperator
  );

  if (!operatorFromOptions) {
    return filter?.filterOperators?.[0];
  }

  return operatorFromOptions;
};

const currentOperator = computed(() =>
  getOperator(currentFilter.value, filterOperator.value)
);

const getInputType = (operator, filter) =>
  operator.inputOverride ?? filter.inputType;

const inputType = computed(() =>
  getInputType(currentOperator.value, currentFilter.value)
);

const queryOperatorOptions = computed(() => {
  return [
    {
      label: t(`FILTER.QUERY_DROPDOWN_LABELS.AND`),
      value: 'and',
      icon: h('span', { class: 'i-lucide-ampersands !text-n-blue-11' }),
    },
    {
      label: t(`FILTER.QUERY_DROPDOWN_LABELS.OR`),
      value: 'or',
      icon: h('span', { class: 'i-woot-logic-or !text-n-blue-11' }),
    },
  ];
});

const booleanOptions = computed(() => [
  { id: true, name: t('FILTER.ATTRIBUTE_LABELS.TRUE') },
  { id: false, name: t('FILTER.ATTRIBUTE_LABELS.FALSE') },
]);

const validationError = computed(() => {
  // TOOD: Migrate validateSingleFilter to use camelcase and then remove useSnakeCase here too
  return validateSingleFilter(
    useSnakeCase({
      attributeKey: attributeKey.value,
      filterOperator: filterOperator.value,
      values: values.value,
    })
  );
});

const inputFieldType = computed(() => {
  if (inputType.value === 'date') return 'date';
  if (inputType.value === 'number') return 'number';
  return 'text';
});

/**
 * Returns the empty value matching the input of an operator, so the model stays
 * compatible with the component that renders it. For example, a multi-select
 * expects an array while a plain text input expects a string.
 * @param {Object} operator - The selected operator
 * @param {Object} filter - The selected filter type
 * @returns {Array|Object|string}
 */
const emptyValueForInputType = (operator, filter) => {
  const type = getInputType(operator, filter);
  if (type === 'multiSelect') return [];
  if (type === 'funnelStage') return filter.multiple ? [] : {};
  if (['searchSelect', 'booleanSelect'].includes(type)) return {};
  return '';
};

const resetModelOnAttributeKeyChange = newAttributeKey => {
  /**
   * Resets the filter values and operator when the attribute key changes. This ensures that
   * the values and operator remain compatible with the new attribute type. For example,
   * switching from a text field to a multi-select should reset the value from '' (empty string)
   * to an empty array.
   */
  const filter = getFilterFromFilterTypes(newAttributeKey);
  const newOperator = getOperator(filter, filterOperator.value);
  values.value = emptyValueForInputType(newOperator, filter);
  filterOperator.value = newOperator.value;
};

// Operators like `is_present` hide the input, so any previously typed value has to go with it.
// Otherwise it stays in the model and gets persisted when the filter is saved as a folder.
watch(currentOperator, (newOperator, oldOperator) => {
  if (!newOperator || newOperator.value === oldOperator?.value) return;
  if (newOperator.hasInput && oldOperator?.hasInput) return;

  values.value = newOperator.hasInput
    ? emptyValueForInputType(newOperator, currentFilter.value)
    : [];
});

watch([attributeKey, values, filterOperator], () => {
  showErrors.value = false;
});

const validate = () => {
  showErrors.value = true;
  return !validationError.value;
};

const resetValidation = () => {
  showErrors.value = false;
};

defineExpose({ validate, resetValidation });
</script>

<template>
  <li class="list-none">
    <div
      class="flex flex-wrap items-center gap-2 rounded-md"
      :class="{
        'animate-wiggle': showErrors && validationError,
      }"
    >
      <FilterSelect
        v-if="showQueryOperator"
        v-model="queryOperator"
        variant="faded"
        hide-icon
        class="text-sm shrink-0"
        :options="queryOperatorOptions"
      />
      <FilterSelect
        v-model="displayAttributeKey"
        variant="faded"
        class="shrink-0"
        :options="filterTypes"
        @update:model-value="resetModelOnAttributeKeyChange"
      />
      <FilterSelect
        v-model="filterOperator"
        variant="ghost"
        class="shrink-0"
        :options="currentFilter?.filterOperators"
      />
      <div
        :class="
          currentOperator?.hasInput
            ? 'flex items-start gap-2 min-w-0'
            : 'contents'
        "
      >
        <template v-if="currentOperator?.hasInput">
          <MultiSelect
            v-if="inputType === 'multiSelect'"
            v-model="values"
            :options="currentFilter.options"
            dropdown-max-height="max-h-72"
          />
          <FunnelStagePicker
            v-else-if="inputType === 'funnelStage'"
            v-model:attribute-key="attributeKey"
            v-model:values="values"
            :multiple="currentFilter.multiple"
          />
          <SingleSelect
            v-else-if="inputType === 'searchSelect'"
            v-model="values"
            :options="currentFilter.options"
            dropdown-max-height="max-h-64"
          />
          <SingleSelect
            v-else-if="inputType === 'booleanSelect'"
            v-model="values"
            disable-search
            :options="booleanOptions"
          />
          <Input
            v-else
            v-model="values"
            :type="inputFieldType"
            class="[&>input]:h-8 [&>input]:py-1.5 [&>input]:outline-offset-0"
            :placeholder="t('FILTER.INPUT_PLACEHOLDER')"
          />
        </template>
        <Button
          sm
          solid
          slate
          icon="i-lucide-trash"
          class="flex-shrink-0"
          @click.stop="emit('remove')"
        />
      </div>
    </div>
    <span v-if="showErrors && validationError" class="text-sm text-n-ruby-11">
      {{ t(`FILTER.ERRORS.${validationError}`) }}
    </span>
  </li>
</template>
