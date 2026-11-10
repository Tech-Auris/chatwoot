<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import {
  ORIGEM_OPTIONS,
  ORIGEM_NONE_TOKEN,
} from 'dashboard/helper/origemOptions';

const props = defineProps({
  // Every caixa the user can see; the picked ones come in `inboxIds`.
  inboxes: { type: Array, required: true },
});

const period = defineModel('period', { type: String, required: true });
const customFrom = defineModel('customFrom', { type: String, default: '' });
const customTo = defineModel('customTo', { type: String, default: '' });
const origem = defineModel('origem', { type: String, default: '' });
const inboxIds = defineModel('inboxIds', { type: Array, default: () => [] });

const { t } = useI18n();

const PERIODS = ['today', '7d', 'month', 'custom'];
const periodLabel = key =>
  ({
    today: t('HOME_OVERVIEW.FILTERS.TODAY'),
    '7d': t('HOME_OVERVIEW.FILTERS.LAST_7_DAYS'),
    month: t('HOME_OVERVIEW.FILTERS.MONTH'),
    custom: t('HOME_OVERVIEW.FILTERS.CUSTOM'),
  })[key];

// The app styles every <select>/<input> full width with a bottom margin; the
// filter row keeps them inline.
const selectClass =
  '!w-auto !mb-0 h-9 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9';

// Never "Todas": what "all" means differs from one user to the next, so the
// label always names the caixas behind the numbers.
const pickedInboxes = computed(() =>
  inboxIds.value.length
    ? props.inboxes.filter(inbox => inboxIds.value.includes(inbox.id))
    : props.inboxes
);

const inboxesLabel = computed(() => {
  const names = pickedInboxes.value.map(inbox => inbox.name);
  const text =
    names.length > 2
      ? t('HOME_OVERVIEW.FILTERS.INBOXES_MORE', {
          name: names[0],
          count: names.length - 1,
        })
      : names.join(', ');
  return t('HOME_OVERVIEW.FILTERS.INBOXES', { names: text });
});

const inboxesTooltip = computed(() =>
  pickedInboxes.value.map(inbox => inbox.name).join(', ')
);

const isPicked = id => !inboxIds.value.length || inboxIds.value.includes(id);

const toggleInbox = id => {
  const current = inboxIds.value.length
    ? inboxIds.value
    : props.inboxes.map(inbox => inbox.id);
  const next = current.includes(id)
    ? current.filter(item => item !== id)
    : [...current, id];
  // Keeping at least one caixa; all of them picked is the same as none.
  if (!next.length) return;
  inboxIds.value = next.length === props.inboxes.length ? [] : next;
};

const inboxMenu = ref(null);
const showInboxMenu = ref(false);
onClickOutside(inboxMenu, () => {
  showInboxMenu.value = false;
});
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <div
      class="flex overflow-hidden rounded-md outline outline-1 outline-n-weak"
    >
      <button
        v-for="key in PERIODS"
        :key="key"
        type="button"
        class="px-3 text-sm h-9"
        :class="
          period === key
            ? 'bg-n-brand text-white'
            : 'bg-n-solid-1 text-n-slate-11 hover:text-n-slate-12'
        "
        @click="period = key"
      >
        {{ periodLabel(key) }}
      </button>
    </div>
    <template v-if="period === 'custom'">
      <label class="flex items-center gap-1 text-sm text-n-slate-11">
        {{ t('HOME_OVERVIEW.FILTERS.FROM') }}
        <input v-model="customFrom" type="date" :class="selectClass" />
      </label>
      <label class="flex items-center gap-1 text-sm text-n-slate-11">
        {{ t('HOME_OVERVIEW.FILTERS.TO') }}
        <input v-model="customTo" type="date" :class="selectClass" />
      </label>
    </template>
    <select v-model="origem" :class="selectClass">
      <option value="">{{ t('HOME_OVERVIEW.FILTERS.ORIGEM_ALL') }}</option>
      <option v-for="option in ORIGEM_OPTIONS" :key="option" :value="option">
        {{ option }}
      </option>
      <option :value="ORIGEM_NONE_TOKEN">
        {{ t('HOME_OVERVIEW.FILTERS.ORIGEM_NONE') }}
      </option>
    </select>
    <div ref="inboxMenu" class="relative">
      <button
        type="button"
        :title="inboxesTooltip"
        :class="selectClass"
        class="inline-flex items-center max-w-xs gap-1"
        @click="showInboxMenu = !showInboxMenu"
      >
        <span class="truncate">{{ inboxesLabel }}</span>
        <span class="flex-shrink-0 i-lucide-chevron-down size-3.5" />
      </button>
      <ul
        v-if="showInboxMenu"
        class="absolute z-10 flex flex-col gap-1 p-2 mt-1 overflow-auto rounded-md shadow-lg max-h-72 min-w-56 bg-n-solid-1 outline outline-1 outline-n-weak"
      >
        <li v-for="inbox in inboxes" :key="inbox.id">
          <label
            class="flex items-center gap-2 px-1 text-sm cursor-pointer text-n-slate-12"
          >
            <input
              type="checkbox"
              :checked="isPicked(inbox.id)"
              @change="toggleInbox(inbox.id)"
            />
            {{ inbox.name }}
          </label>
        </li>
      </ul>
    </div>
  </div>
</template>
