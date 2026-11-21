<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import PipelinesAPI from 'dashboard/api/pipelines';
import { elapsedSince } from 'dashboard/routes/dashboard/funnel/pipelineFormatters';

// "Funis" block of the contact panel: the clinic pipelines the contact is in
// and the stage of each.
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const entries = ref([]);

const fetchEntries = async () => {
  try {
    const { data } = await PipelinesAPI.contactEntries(props.contactId);
    entries.value = data?.payload || [];
  } catch (error) {
    entries.value = [];
  }
};

watch(() => props.contactId, fetchEntries, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-2 px-4 py-2">
    <div
      v-for="entry in entries"
      :key="entry.id"
      class="flex items-center gap-2 min-w-0"
    >
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
    </div>
    <p v-if="!entries.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('PIPELINES.HEADER.EMPTY') }}
    </p>
  </div>
</template>
