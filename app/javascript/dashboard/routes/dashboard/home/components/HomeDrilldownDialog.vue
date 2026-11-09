<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import HomeAPI from 'dashboard/api/home';

// The conversations behind one card of the Início page, same look as the
// Conversão do funil drill-down. Same period and filters as the page, so the
// list adds up to the number that was clicked.
const props = defineProps({
  filters: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();

// Per card: what the date column means and what the extra column shows.
const COLUMNS = {
  new_leads_today: { date: 'ARRIVED_AT' },
  leads: { date: 'ARRIVED_AT' },
  off_hours_leads: { date: 'ARRIVED_AT' },
  booked_today: { date: 'BOOKED_AT', detail: 'BOOKED_BY' },
  appointments: { date: 'BOOKED_AT', detail: 'BOOKED_BY' },
  off_hours_appointments: { date: 'BOOKED_AT', detail: 'BOOKED_BY' },
  tomorrow: { date: 'APPOINTMENT_AT', detail: 'STATUS' },
  follow_up_leads: { date: 'FOLLOW_UP_AT', detail: 'FOLLOW_UP_STEP' },
  no_shows: { date: 'NO_SHOW_AT', detail: 'MOVED_BY' },
  attendances: { date: 'ATTENDED_AT', detail: 'MOVED_BY' },
};

const dialogRef = ref(null);
const target = ref(null);
const rows = ref([]);
const meta = ref({ current_page: 1, per_page: 50, total_count: 0 });
const loading = ref(false);
const failed = ref(false);

const columns = computed(() => COLUMNS[target.value?.metric] || {});

const title = computed(() =>
  target.value
    ? t('HOME_OVERVIEW.DRILLDOWN.TITLE', {
        card: target.value.title,
        count: meta.value.total_count,
      })
    : ''
);

const fetchPage = async page => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await HomeAPI.drilldown({
      ...props.filters,
      metric: target.value.metric,
      page,
    });
    rows.value = data.rows;
    meta.value = data.meta;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

// `next` is { metric, title, count }.
const open = next => {
  target.value = next;
  rows.value = [];
  meta.value = { current_page: 1, per_page: 50, total_count: next.count };
  dialogRef.value?.open();
  fetchPage(1);
};

const conversationUrl = row =>
  `/app/accounts/${route.params.accountId}/conversations/${row.id}`;

const formatDateTime = timestamp =>
  new Date(timestamp * 1000).toLocaleString(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const dash = value => value || t('HOME_OVERVIEW.WAITING_DIALOG.DASH');

const formatDetail = row => {
  if (columns.value.detail === 'STATUS') {
    return t(`HOME_OVERVIEW.DRILLDOWN.STATUSES.${row.detail.toUpperCase()}`);
  }
  if (columns.value.detail === 'FOLLOW_UP_STEP') {
    return t('HOME_OVERVIEW.DRILLDOWN.STEP', { step: row.detail });
  }
  return row.detail || t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.AUTOMATION');
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('HOME_OVERVIEW.DRILLDOWN.DESCRIPTION')"
    width="7xl"
  >
    <div class="flex flex-col gap-3">
      <div
        v-if="failed"
        class="px-4 py-3 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-12"
      >
        {{ t('HOME_OVERVIEW.DRILLDOWN.ERROR') }}
      </div>
      <div
        v-else-if="loading && !rows.length"
        class="flex justify-center py-10"
      >
        <Spinner :size="24" class="text-n-brand" />
      </div>
      <div
        v-else-if="!rows.length"
        class="py-10 text-sm text-center text-n-slate-11"
      >
        {{ t('HOME_OVERVIEW.METRICS.EMPTY') }}
      </div>
      <div
        v-else
        class="overflow-x-auto rounded-lg outline outline-1 outline-n-container"
        :class="{ 'opacity-50': loading }"
      >
        <table class="w-full text-sm">
          <thead class="text-xs bg-n-slate-2 text-n-slate-11">
            <tr>
              <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
                {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.CONVERSATION') }}
              </th>
              <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
                {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.CONTACT') }}
              </th>
              <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
                {{ t(`HOME_OVERVIEW.DRILLDOWN.COLUMNS.${columns.date}`) }}
              </th>
              <th
                v-if="columns.detail"
                class="px-3 py-2 font-medium text-left whitespace-nowrap"
              >
                {{ t(`HOME_OVERVIEW.DRILLDOWN.COLUMNS.${columns.detail}`) }}
              </th>
              <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
                {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.INBOX') }}
              </th>
              <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
                {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.SOURCE') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak text-n-slate-12">
            <tr v-for="row in rows" :key="row.id">
              <td class="px-3 py-2 whitespace-nowrap">
                <a
                  :href="conversationUrl(row)"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="font-mono text-n-brand hover:underline"
                >
                  {{
                    t('HOME_OVERVIEW.WAITING_DIALOG.HASH_ID', { id: row.id })
                  }}
                </a>
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <div>{{ dash(row.contact_name) }}</div>
                <div v-if="row.contact_phone" class="text-xs text-n-slate-11">
                  {{ row.contact_phone }}
                </div>
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ formatDateTime(row.at) }}
              </td>
              <td v-if="columns.detail" class="px-3 py-2 whitespace-nowrap">
                {{ formatDetail(row) }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ dash(row.inbox_name) }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ dash(row.origem) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <PaginationFooter
        v-if="meta.total_count > meta.per_page"
        :current-page="meta.current_page"
        :total-items="meta.total_count"
        :items-per-page="meta.per_page"
        class="!px-0"
        @update:current-page="fetchPage"
      />
    </div>
    <template #footer>
      <div class="flex justify-center">
        <Button
          type="button"
          color="blue"
          class="min-w-32"
          :label="t('HOME_OVERVIEW.WAITING_DIALOG.CLOSE')"
          @click="dialogRef.close()"
        />
      </div>
    </template>
  </Dialog>
</template>
