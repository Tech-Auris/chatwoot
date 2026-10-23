<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// One condition of an audience rule or exclusion: field, "é / não é" (or
// "inclui / não inclui" for labels) and one value.
const props = defineProps({
  fields: { type: Array, required: true },
  operators: { type: Array, required: true },
  options: { type: Array, required: true },
});

const emit = defineEmits(['remove']);

const condition = defineModel({ type: Object, required: true });

const { t } = useI18n();

const update = changes => {
  condition.value = { ...condition.value, ...changes };
};

// Changing the field resets the operator and the value, which belong to it.
const field = computed({
  get: () => condition.value.attribute_key,
  set: key => {
    update({ attribute_key: key, filter_operator: 'equal_to', values: [] });
  },
});

const operator = computed({
  get: () => condition.value.filter_operator,
  set: value => {
    update({ filter_operator: value });
  },
});

const value = computed({
  get: () => condition.value.values?.[0] ?? '',
  set: picked => {
    update({ values: [picked] });
  },
});
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <Select
      v-model="field"
      :options="props.fields"
      :placeholder="t('AUDIENCES.FORM.FIELD_PLACEHOLDER')"
    />
    <Select v-model="operator" :options="props.operators" />
    <Select
      v-model="value"
      :options="props.options"
      :placeholder="t('AUDIENCES.FORM.VALUE_PLACEHOLDER')"
    />
    <Button
      icon="i-lucide-x"
      variant="ghost"
      color="slate"
      size="sm"
      :aria-label="t('AUDIENCES.FORM.REMOVE_CONDITION')"
      @click="emit('remove')"
    />
  </div>
</template>
