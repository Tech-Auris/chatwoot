<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import PipelinesAPI from 'dashboard/api/pipelines';
import { elapsedSince } from 'dashboard/routes/dashboard/funnel/pipelineFormatters';
import { dynamicTime } from 'shared/helpers/timeHelper';

// "Funis" block of the contact panel: the clinic pipelines the contact is in,
// the stage of each and, on click, the history of that pass (who or what
// moved it, when and why).
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const entries = ref([]);
const openEntryId = ref(null);
const events = ref([]);

const fetchEntries = async () => {
  try {
    const { data } = await PipelinesAPI.contactEntries(props.contactId);
    entries.value = data?.payload || [];
  } catch (error) {
    entries.value = [];
  }
};

watch(() => props.contactId, fetchEntries, { immediate: true });

const toggleHistory = async entry => {
  if (openEntryId.value === entry.id) {
    openEntryId.value = null;
    return;
  }
  openEntryId.value = entry.id;
  events.value = [];
  const { data } = await PipelinesAPI.entryEvents(entry.id);
  events.value = (data?.payload || []).slice().reverse();
};

const SOURCE_KEYS = {
  automation: 'PIPELINES.HISTORY.BY_AUTOMATION',
  api: 'PIPELINES.HISTORY.BY_API',
  ai: 'PIPELINES.HISTORY.BY_AI',
};

const eventTitle = event =>
  event.from_stage
    ? t('PIPELINES.HISTORY.MOVED', {
        from: event.from_stage.name,
        to: event.to_stage?.name || '--',
      })
    : t('PIPELINES.HISTORY.ENTERED', { stage: event.to_stage?.name || '--' });

const eventDetails = event =>
  [
    event.user?.name ||
      (SOURCE_KEYS[event.source] && t(SOURCE_KEYS[event.source])),
    dynamicTime(event.created_at),
    event.loss_reason?.name,
    event.reason,
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<template>
  <div class="flex flex-col gap-2 px-4 py-2">
    <div v-for="entry in entries" :key="entry.id" class="flex flex-col gap-1">
      <button
        type="button"
        class="flex items-center gap-2 min-w-0 text-start"
        :title="t('PIPELINES.HISTORY.HISTORY')"
        @click="toggleHistory(entry)"
      >
        <span
          class="i-lucide-chevron-right size-3.5 text-n-slate-11 transition-transform flex-shrink-0"
          :class="{ 'rotate-90': openEntryId === entry.id }"
        />
        <span class="flex-1 min-w-0 text-sm text-n-slate-12 truncate">
          {{ entry.pipeline_name }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
        >
          <span
            class="inline-block size-2 rounded-full"
            :style="{ backgroundColor: entry.stage.color }"
          />
          {{ entry.stage.name }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ elapsedSince(t, entry.stage_entered_at) }}
        </span>
      </button>
      <ol
        v-if="openEntryId === entry.id"
        class="flex flex-col gap-1.5 m-0 ms-5 ps-3 border-s border-n-weak list-none"
      >
        <li v-for="event in events" :key="event.id" class="flex flex-col">
          <span class="text-xs text-n-slate-12">{{ eventTitle(event) }}</span>
          <span class="text-xs text-n-slate-11">{{ eventDetails(event) }}</span>
        </li>
        <li v-if="!events.length" class="text-xs text-n-slate-11">
          {{ t('PIPELINES.HISTORY.EMPTY') }}
        </li>
      </ol>
    </div>
    <p v-if="!entries.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('PIPELINES.HEADER.EMPTY') }}
    </p>
  </div>
</template>
