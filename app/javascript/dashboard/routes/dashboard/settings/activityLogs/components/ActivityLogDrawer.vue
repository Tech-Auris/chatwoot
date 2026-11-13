<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import ActivityLogsAPI from 'dashboard/api/activityLogs';
import { FILTERED, formatDateTime, formatValue, typeKey } from '../helpers';

const props = defineProps({
  logId: { type: Number, default: null },
});

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();

const log = ref(null);
const loading = ref(false);

const changes = computed(() =>
  Object.entries(log.value?.audited_changes || {}).map(
    ([field, [before, after]]) => ({
      field,
      label: t(`ACTIVITY_LOGS.FIELDS.${field}`, field),
      filtered: after === FILTERED,
      before: formatValue(before),
      after: formatValue(after),
    })
  )
);

const title = computed(() => {
  if (!log.value) return '';
  const type = t(
    `ACTIVITY_LOGS.TYPES.${typeKey(log.value.auditable_type)}`,
    log.value.auditable_type
  );
  const name = log.value.auditable_label
    ? ` · ${log.value.auditable_label}`
    : '';
  return `${type} #${log.value.auditable_id}${name}`;
});

const actorLabel = entry => entry.actor_label || t('ACTIVITY_LOGS.SYSTEM');

const subtitle = computed(() => {
  if (!log.value) return '';
  const parts = [actorLabel(log.value), formatDateTime(log.value.created_at)];
  if (log.value.ip_address) parts.push(`IP ${log.value.ip_address}`);
  return parts.join(' · ');
});

watch(
  () => props.logId,
  async id => {
    if (!id) {
      log.value = null;
      return;
    }
    loading.value = true;
    try {
      const { data } = await ActivityLogsAPI.show(id);
      log.value = data;
    } catch {
      useAlert(t('ACTIVITY_LOGS.ERRORS.FETCH'));
      emit('close');
    } finally {
      loading.value = false;
    }
  }
);
</script>

<template>
  <aside
    v-if="logId"
    class="fixed top-0 right-0 h-full w-full max-w-xl bg-n-solid-1 border-l border-n-weak shadow-2xl z-40 flex flex-col"
  >
    <header
      class="flex items-start justify-between p-5 border-b border-n-weak gap-3"
    >
      <div v-if="log" class="min-w-0">
        <h2 class="text-base font-semibold text-n-slate-12 truncate">
          {{ title }}
        </h2>
        <p class="text-xs text-n-slate-11 mt-0.5">{{ subtitle }}</p>
      </div>
      <Button
        icon="i-lucide-x"
        sm
        ghost
        slate
        class="flex-shrink-0 ml-auto"
        @click="emit('close')"
      />
    </header>

    <div v-if="loading" class="flex justify-center p-8">
      <Spinner />
    </div>

    <div v-else-if="log" class="flex-1 overflow-y-auto p-5 space-y-6">
      <section class="space-y-3">
        <h3 class="text-xs font-semibold uppercase text-n-slate-11">
          {{ t('ACTIVITY_LOGS.DETAIL.CHANGES') }}
        </h3>
        <p v-if="changes.length === 0" class="text-sm text-n-slate-11">
          {{ t('ACTIVITY_LOGS.DETAIL.NO_CHANGES') }}
        </p>
        <div v-for="change in changes" :key="change.field" class="space-y-1">
          <p class="text-sm font-medium text-n-slate-12">{{ change.label }}</p>
          <div
            class="flex flex-wrap items-center gap-2 border border-n-weak rounded-lg p-2 text-sm"
          >
            <span v-if="change.filtered" class="text-n-slate-11">
              {{ t('ACTIVITY_LOGS.DETAIL.FILTERED') }}
            </span>
            <template v-else>
              <span
                class="px-1.5 rounded bg-n-ruby-3 text-n-ruby-11 line-through break-all"
              >
                {{ change.before }}
              </span>
              <span class="i-lucide-arrow-right size-3.5 text-n-slate-11" />
              <span class="px-1.5 rounded bg-n-teal-3 text-n-teal-11 break-all">
                {{ change.after }}
              </span>
            </template>
          </div>
        </div>
      </section>

      <section v-if="log.history.length > 1" class="space-y-2">
        <h3 class="text-xs font-semibold uppercase text-n-slate-11">
          {{ t('ACTIVITY_LOGS.DETAIL.HISTORY') }}
        </h3>
        <button
          v-for="entry in log.history"
          :key="entry.id"
          type="button"
          class="block w-full text-left text-sm rounded px-2 py-1 hover:bg-n-alpha-1"
          :class="
            entry.id === log.id
              ? 'text-n-slate-12 font-medium'
              : 'text-n-slate-11'
          "
          @click="emit('select', entry.id)"
        >
          {{ formatDateTime(entry.created_at) }} · {{ actorLabel(entry) }}
          {{ t(`ACTIVITY_LOGS.ACTIONS.${entry.action}`).toLowerCase() }}
          <span v-if="entry.changed_fields.length && entry.action === 'update'">
            ·
            {{
              entry.changed_fields
                .map(field => t(`ACTIVITY_LOGS.FIELDS.${field}`, field))
                .join(', ')
            }}
          </span>
        </button>
      </section>
    </div>
  </aside>
</template>
