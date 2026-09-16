<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  ORIGEM_OPTIONS,
  ORIGEM_NONE_TOKEN,
} from 'dashboard/helper/origemOptions';

const props = defineProps({
  inboxId: { type: [Number, String], default: '' },
  fromDate: { type: String, default: '' },
  toDate: { type: String, default: '' },
  hideClosed: { type: Boolean, default: false },
  origem: { type: String, default: '' },
});

const emit = defineEmits([
  'update:inboxId',
  'update:fromDate',
  'update:toDate',
  'update:hideClosed',
  'update:origem',
  'reset',
]);

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const inboxOptions = computed(() =>
  [...inboxes.value].sort((a, b) => a.name.localeCompare(b.name))
);

const origemOptions = ORIGEM_OPTIONS;

const hasActiveFilters = computed(
  () =>
    Boolean(props.inboxId) ||
    Boolean(props.fromDate) ||
    Boolean(props.toDate) ||
    Boolean(props.origem) ||
    props.hideClosed
);

const onInboxChange = event => emit('update:inboxId', event.target.value);
const onFromChange = event => emit('update:fromDate', event.target.value);
const onToChange = event => emit('update:toDate', event.target.value);
const onHideClosedChange = event =>
  emit('update:hideClosed', event.target.checked);
const onOrigemChange = event => emit('update:origem', event.target.value);
const onReset = () => emit('reset');
</script>

<template>
  <div
    class="flex flex-wrap items-end gap-3 px-6 py-3 border-b border-n-weak bg-n-surface-1"
  >
    <label class="flex flex-col gap-1 w-48">
      <span class="text-xs text-n-slate-11">
        {{ t('FUNNEL.FILTERS.INBOX') }}
      </span>
      <select
        :value="inboxId"
        class="h-10 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9"
        @change="onInboxChange"
      >
        <option value="">
          {{ t('FUNNEL.FILTERS.INBOX_ANY') }}
        </option>
        <option v-for="inbox in inboxOptions" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
    </label>

    <label class="flex flex-col gap-1 w-48">
      <span class="text-xs text-n-slate-11">
        {{ t('FUNNEL.FILTERS.FROM_DATE') }}
      </span>
      <input
        type="date"
        :value="fromDate"
        class="h-8 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9"
        @change="onFromChange"
      />
    </label>

    <label class="flex flex-col gap-1 w-48">
      <span class="text-xs text-n-slate-11">
        {{ t('FUNNEL.FILTERS.TO_DATE') }}
      </span>
      <input
        type="date"
        :value="toDate"
        class="h-8 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9"
        @change="onToChange"
      />
    </label>

    <label class="flex flex-col gap-1 w-48">
      <span class="text-xs text-n-slate-11">
        {{ t('FUNNEL.FILTERS.ORIGEM') }}
      </span>
      <select
        :value="origem"
        class="h-10 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9"
        @change="onOrigemChange"
      >
        <option value="">
          {{ t('FUNNEL.FILTERS.ORIGEM_ANY') }}
        </option>
        <option v-for="opt in origemOptions" :key="opt" :value="opt">
          {{ opt }}
        </option>
        <option :value="ORIGEM_NONE_TOKEN">
          {{ t('FUNNEL.FILTERS.ORIGEM_NONE') }}
        </option>
      </select>
    </label>

    <label class="flex flex-col w-48">
      <span class="inline-flex items-top gap-2 h-11 text-xs text-n-slate-12">
        <input
          type="checkbox"
          :checked="hideClosed"
          class="size-4 rounded border-n-weak"
          @change="onHideClosedChange"
        />
        {{ t('FUNNEL.FILTERS.HIDE_CLOSED') }}
      </span>
    </label>

    <div v-if="hasActiveFilters" class="flex flex-col w-48">
      <span class="inline-flex items-top gap-2 h-16 text-xs">
        <button
          type="button"
          class="px-3 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
          @click="onReset"
        >
          {{ t('FUNNEL.FILTERS.RESET') }}
        </button>
      </span>
    </div>
  </div>
</template>
