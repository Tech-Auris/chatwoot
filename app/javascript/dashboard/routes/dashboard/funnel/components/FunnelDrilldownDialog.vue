<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

// Same period and filters as the report on screen, so the list has exactly as
// many rows as the number that was clicked.
const props = defineProps({
  filters: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();

const dialogRef = ref(null);
const target = ref(null);
const rows = ref([]);
const meta = ref({ current_page: 1, per_page: 50, total_count: 0 });
const loading = ref(false);
const failed = ref(false);

const isLoss = computed(() => target.value?.kind === 'loss');

const title = computed(() => {
  if (!target.value) return '';
  const count = meta.value.total_count;
  if (target.value.kind === 'ad') {
    return t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.TITLE_AD', {
      ad: target.value.name,
      count,
    });
  }
  if (!isLoss.value) {
    return t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.TITLE_STAGE', {
      stage: target.value.name,
      count,
    });
  }
  if (target.value.name) {
    return t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.TITLE_LOSS_REASON', {
      reason: target.value.name,
      count,
    });
  }
  return t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.TITLE_LOSS', { count });
});

const fetchPage = async page => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await SummaryReportsAPI.getFunnelConversionDrilldown({
      ...props.filters,
      stageKey: target.value.stageKey,
      kind: target.value.kind,
      lossReasonId: target.value.lossReasonId,
      sourceId: target.value.sourceId,
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

// `next` is { stageKey, name, count } for a chart stage,
// { kind: 'loss', lossReasonId?, name?, count } for the losses, or
// { kind: 'ad', sourceId, name, count } for one ad's leads.
const open = next => {
  target.value = next;
  rows.value = [];
  meta.value = { current_page: 1, per_page: 50, total_count: next.count };
  dialogRef.value?.open();
  fetchPage(1);
};

const conversationUrl = row =>
  `/app/accounts/${route.params.accountId}/conversations/${row.conversation_id}`;

const formatDateTime = iso =>
  new Date(iso).toLocaleString(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const dash = value => value || t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.DASH');

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="$t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.DESCRIPTION')"
    width="7xl"
  >
    <div class="flex flex-col gap-3">
      <div
        v-if="failed"
        class="px-4 py-3 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
      >
        {{ $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.ERROR') }}
      </div>

      <div
        v-else-if="loading && !rows.length"
        class="flex justify-center py-10"
      >
        <Spinner :size="24" class="text-n-brand" />
      </div>

      <div
        v-else-if="!rows.length"
        class="py-10 text-center text-sm text-n-slate-11"
      >
        {{ $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.EMPTY_STATE') }}
      </div>

      <div
        v-else
        class="overflow-x-auto rounded-lg outline outline-1 outline-n-container"
        :class="{ 'opacity-50': loading }"
      >
        <table class="w-full text-sm">
          <thead class="bg-n-slate-2 text-n-slate-11 text-xs">
            <tr>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{
                  $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.CONVERSATION')
                }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{ $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.CONTACT') }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{
                  isLoss
                    ? $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.LOST_AT')
                    : $t(
                        'FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.ENTERED_AT'
                      )
                }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{
                  isLoss
                    ? $t(
                        'FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.LOSS_REASON'
                      )
                    : $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.STAGE')
                }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{
                  $t(
                    'FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.PREVIOUS_STAGE'
                  )
                }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{ $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.MOVED_BY') }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{ $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.INBOX') }}
              </th>
              <th class="px-3 py-2 text-left font-medium whitespace-nowrap">
                {{ $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.COLUMNS.SOURCE') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak text-n-slate-12">
            <tr
              v-for="row in rows"
              :key="`${row.conversation_id}-${row.entered_at}`"
              class="align-top"
            >
              <td class="px-3 py-2 whitespace-nowrap">
                <a
                  :href="conversationUrl(row)"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-n-brand hover:underline font-mono"
                >
                  {{
                    $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.HASH_ID', {
                      id: row.conversation_id,
                    })
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
                {{ formatDateTime(row.entered_at) }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ dash(isLoss ? row.loss_reason : row.stage) }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ dash(row.previous_stage) }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{
                  row.moved_by ||
                  $t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.AUTOMATION')
                }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ dash(row.inbox_name) }}
              </td>
              <td class="px-3 py-2">
                <div>{{ dash(row.origem) }}</div>
                <div v-if="row.ad_title" class="text-xs text-n-slate-11">
                  {{ row.ad_title }}
                </div>
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
          :label="$t('FUNNEL_CONVERSION_REPORTS.DRILLDOWN.CLOSE')"
          @click="dialogRef.close()"
        />
      </div>
    </template>
  </Dialog>
</template>
