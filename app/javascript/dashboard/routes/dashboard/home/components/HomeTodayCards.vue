<script setup>
import { useI18n } from 'vue-i18n';
import HomeDrillButton from './HomeDrillButton.vue';

defineProps({
  today: { type: Object, required: true },
});

// `drill` carries the card: new_leads_today, booked_today or tomorrow.
// "Sem resposta" has its own dialog, with the rows that come with the page.
const emit = defineEmits(['drill', 'openWaiting']);

const { t } = useI18n();

const cardClass =
  'px-4 py-3 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container';
</script>

<template>
  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
    <div :class="cardClass">
      <div class="text-sm text-n-slate-11">
        {{ t('HOME_OVERVIEW.TODAY.NEW_LEADS') }}
      </div>
      <div class="flex items-center gap-1 mt-1">
        <span class="text-2xl font-semibold text-n-slate-12">
          {{ today.new_leads }}
        </span>
        <HomeDrillButton
          v-if="today.new_leads"
          @click="emit('drill', 'new_leads_today')"
        />
      </div>
    </div>
    <div :class="cardClass">
      <div class="text-sm text-n-slate-11">
        {{ t('HOME_OVERVIEW.TODAY.BOOKED') }}
      </div>
      <div class="flex items-center gap-1 mt-1">
        <span class="text-2xl font-semibold text-n-slate-12">
          {{ today.booked }}
        </span>
        <HomeDrillButton
          v-if="today.booked"
          @click="emit('drill', 'booked_today')"
        />
      </div>
    </div>
    <div
      class="px-4 py-3 rounded-xl outline outline-1"
      :class="
        today.waiting.count
          ? 'bg-n-amber-2 outline-n-amber-6'
          : 'bg-n-solid-2 outline-n-container'
      "
    >
      <div class="text-sm text-n-slate-11">
        {{ t('HOME_OVERVIEW.TODAY.WAITING') }}
      </div>
      <div class="flex items-center gap-1 mt-1">
        <span
          class="text-2xl font-semibold"
          :class="
            today.waiting.count
              ? 'text-[#d97706] dark:text-n-amber-11'
              : 'text-n-slate-12'
          "
        >
          {{ today.waiting.count }}
        </span>
        <HomeDrillButton
          v-if="today.waiting.count"
          @click="emit('openWaiting')"
        />
      </div>
    </div>
    <div :class="cardClass">
      <div class="text-sm text-n-slate-11">
        {{ t('HOME_OVERVIEW.TODAY.TOMORROW') }}
      </div>
      <div class="flex items-center gap-1 mt-1">
        <span class="text-2xl font-semibold text-n-slate-12">
          {{ today.tomorrow.scheduled }}
        </span>
        <HomeDrillButton
          v-if="today.tomorrow.scheduled"
          @click="emit('drill', 'tomorrow')"
        />
        <span class="ml-1 text-xs text-n-slate-11">
          {{
            t('HOME_OVERVIEW.TODAY.TOMORROW_DETAIL', {
              confirmed: today.tomorrow.confirmed,
            })
          }}
        </span>
      </div>
    </div>
  </div>
</template>
