<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import ActivityLogDrawer from './components/ActivityLogDrawer.vue';
import ActivityLogsAPI from 'dashboard/api/activityLogs';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { SOURCE_CLASSES, formatDateTime, typeKey } from './helpers';

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const PERIODS = [7, 30, 90, 365];
const ACTIONS = ['create', 'update', 'destroy', 'merge', 'sign_in', 'sign_out'];
const SOURCES = ['dashboard', 'api', 'job', 'super_admin', 'login'];

const logs = ref([]);
const meta = ref({ count: 0, current_page: 1, per_page: 25 });
const auditableTypes = ref([]);
const loading = ref(true);
const exporting = ref(false);
const selectedLogId = ref(null);

const filters = ref({
  period: 7,
  user_id: '',
  auditable_type: '',
  log_action: '',
  source: '',
  q: '',
});

const selectClass =
  'bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand';

const queryParams = computed(() => {
  const { period, ...rest } = filters.value;
  const since = new Date(Date.now() - period * 24 * 60 * 60 * 1000);
  return { ...rest, since: since.toISOString() };
});

const typeLabel = type => t(`ACTIVITY_LOGS.TYPES.${typeKey(type)}`, type || '');

const fieldLabel = field => t(`ACTIVITY_LOGS.FIELDS.${field}`, field);

const actorLabel = log => log.actor_label || t('ACTIVITY_LOGS.SYSTEM');

const recordLabel = log => {
  const name = log.auditable_label ? ` · ${log.auditable_label}` : '';
  return `${typeLabel(log.auditable_type)} #${log.auditable_id}${name}`;
};

const fetchLogs = async (page = 1) => {
  loading.value = true;
  try {
    const { data } = await ActivityLogsAPI.get({ ...queryParams.value, page });
    logs.value = data.payload;
    meta.value = data.meta;
    auditableTypes.value = data.meta.auditable_types;
  } catch {
    useAlert(t('ACTIVITY_LOGS.ERRORS.FETCH'));
  } finally {
    loading.value = false;
  }
};

const debouncedFetch = useDebounceFn(() => fetchLogs(1), 400);

watch(
  () => ({ ...filters.value }),
  (next, previous) => {
    if (next.q !== previous.q) debouncedFetch();
    else fetchLogs(1);
  }
);

const exportCsv = async () => {
  exporting.value = true;
  try {
    const { data } = await ActivityLogsAPI.export(queryParams.value);
    downloadCsvFile(t('ACTIVITY_LOGS.EXPORT.FILE_NAME'), data);
  } catch {
    useAlert(t('ACTIVITY_LOGS.ERRORS.EXPORT'));
  } finally {
    exporting.value = false;
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  fetchLogs(1);
});
</script>

<template>
  <SettingsLayout
    :is-loading="loading && logs.length === 0"
    :loading-message="t('ACTIVITY_LOGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('ACTIVITY_LOGS.HEADER.TITLE')"
        :description="t('ACTIVITY_LOGS.HEADER.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-download"
            :label="t('ACTIVITY_LOGS.EXPORT.BUTTON')"
            :is-loading="exporting"
            :disabled="exporting"
            @click="exportCsv"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="grid gap-4">
        <div class="flex flex-wrap items-end gap-3">
          <select v-model="filters.period" :class="selectClass">
            <option v-for="days in PERIODS" :key="days" :value="days">
              {{ t('ACTIVITY_LOGS.FILTERS.LAST_DAYS', { days }) }}
            </option>
          </select>
          <select v-model="filters.user_id" :class="selectClass">
            <option value="">{{ t('ACTIVITY_LOGS.FILTERS.ALL_USERS') }}</option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
          <select v-model="filters.auditable_type" :class="selectClass">
            <option value="">{{ t('ACTIVITY_LOGS.FILTERS.ALL_TYPES') }}</option>
            <option v-for="type in auditableTypes" :key="type" :value="type">
              {{ typeLabel(type) }}
            </option>
          </select>
          <select v-model="filters.log_action" :class="selectClass">
            <option value="">
              {{ t('ACTIVITY_LOGS.FILTERS.ALL_ACTIONS') }}
            </option>
            <option v-for="action in ACTIONS" :key="action" :value="action">
              {{ t(`ACTIVITY_LOGS.ACTIONS.${action}`) }}
            </option>
          </select>
          <select v-model="filters.source" :class="selectClass">
            <option value="">
              {{ t('ACTIVITY_LOGS.FILTERS.ALL_SOURCES') }}
            </option>
            <option v-for="source in SOURCES" :key="source" :value="source">
              {{ t(`ACTIVITY_LOGS.SOURCES.${source}`) }}
            </option>
          </select>
          <input
            v-model="filters.q"
            type="text"
            class="flex-1 min-w-64 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10"
            :placeholder="t('ACTIVITY_LOGS.FILTERS.SEARCH_PLACEHOLDER')"
          />
        </div>

        <div
          v-if="!loading && logs.length === 0"
          class="py-12 text-center text-n-slate-11"
        >
          {{ t('ACTIVITY_LOGS.EMPTY') }}
        </div>

        <div v-else class="border border-n-weak rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1 text-n-slate-11 text-xs uppercase">
              <tr>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('ACTIVITY_LOGS.TABLE.WHEN') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('ACTIVITY_LOGS.TABLE.WHO') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('ACTIVITY_LOGS.TABLE.WHAT') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('ACTIVITY_LOGS.TABLE.SOURCE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="log in logs"
                :key="log.id"
                class="hover:bg-n-alpha-1 cursor-pointer text-n-slate-12"
                :class="{ 'bg-n-alpha-1': selectedLogId === log.id }"
                @click="selectedLogId = log.id"
              >
                <td class="px-4 py-3 whitespace-nowrap">
                  {{ formatDateTime(log.created_at) }}
                </td>
                <td class="px-4 py-3">{{ actorLabel(log) }}</td>
                <td class="px-4 py-3">
                  {{ t(`ACTIVITY_LOGS.ACTIONS.${log.action}`) }}
                  <span class="font-medium">{{ recordLabel(log) }}</span>
                  <span
                    v-if="log.changed_fields.length && log.action === 'update'"
                    class="text-n-slate-11"
                  >
                    ·
                    {{ log.changed_fields.map(fieldLabel).join(', ') }}
                  </span>
                </td>
                <td class="px-4 py-3">
                  <span
                    class="px-2 py-0.5 rounded-md text-xs font-medium whitespace-nowrap"
                    :class="SOURCE_CLASSES[log.source]"
                  >
                    {{ t(`ACTIVITY_LOGS.SOURCES.${log.source}`) }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <div class="px-4 py-3 border-t border-n-weak">
            <PaginationFooter
              :current-page="meta.current_page"
              :total-items="meta.count"
              :items-per-page="meta.per_page"
              class="!px-0"
              @update:current-page="fetchLogs"
            />
          </div>
        </div>
      </div>

      <ActivityLogDrawer
        :log-id="selectedLogId"
        @close="selectedLogId = null"
        @select="selectedLogId = $event"
      />
    </template>
  </SettingsLayout>
</template>
