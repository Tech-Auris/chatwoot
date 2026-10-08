<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CampaignsAPI from 'dashboard/api/campaigns';
import Button from 'dashboard/components-next/button/Button.vue';
import CampaignCard from 'dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { debounce } from '@chatwoot/utils';
import { frontendURL } from 'dashboard/helper/URLHelper';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const summary = ref({
  total: 0,
  accepted: 0,
  failed: 0,
  delivered: 0,
  read: 0,
  success_rate: 0,
});
const campaign = ref(null);
const messages = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const failureReasons = ref([]);
const showFailures = ref(false);
// Name or phone (with or without formatting) and status narrow the rows; the
// totals on top keep covering the whole campaign.
const searchQuery = ref('');
const statusFilter = ref('');
const isLoading = ref(false);
const error = ref('');

const campaignId = computed(() => route.params.campaignId);

const STATUS_LABELS = {
  sent: 'SENT',
  delivered: 'DELIVERED',
  read: 'READ',
  failed: 'FAILED',
};

const fetchPage = async (page = 1) => {
  isLoading.value = true;
  error.value = '';

  try {
    const { data } = await CampaignsAPI.report(campaignId.value, {
      page,
      q: searchQuery.value.trim(),
      status: statusFilter.value,
    });
    campaign.value = data.campaign ?? campaign.value;
    summary.value = data.summary ?? summary.value;
    failureReasons.value = data.failure_reasons ?? [];
    messages.value = data.messages ?? [];
    meta.value = data.meta ?? meta.value;
  } catch {
    error.value = t('CAMPAIGN.WHATSAPP.REPORT.ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => fetchPage(1));

const searchFromFirstPage = debounce(() => fetchPage(1), 300);
watch(searchQuery, searchFromFirstPage);
watch(statusFilter, () => fetchPage(1));

const statusOptions = computed(() => [
  { value: '', label: t('CAMPAIGN.WHATSAPP.REPORT.ALL_STATUSES') },
  ...Object.entries(STATUS_LABELS).map(([value, key]) => ({
    value,
    label: t(`CAMPAIGN.WHATSAPP.REPORT.STATUS.${key}`),
  })),
]);
const isFiltering = computed(
  () => !!searchQuery.value.trim() || !!statusFilter.value
);

// Vue reuses this component when only the route param changes, so mounting
// alone doesn't cover moving between two campaign reports. The totals and rows
// are cleared first, otherwise the previous campaign's numbers stay on screen
// and read as the new one's.
watch(campaignId, () => {
  summary.value = {
    total: 0,
    accepted: 0,
    failed: 0,
    delivered: 0,
    read: 0,
    success_rate: 0,
  };
  campaign.value = null;
  messages.value = [];
  failureReasons.value = [];
  meta.value = { current_page: 1, total_pages: 1, total_count: 0 };
  searchQuery.value = '';
  statusFilter.value = '';
  fetchPage(1);
});

const bigNumbers = computed(() => [
  { key: 'TOTAL', value: summary.value.total },
  { key: 'ACCEPTED', value: summary.value.accepted },
  { key: 'DELIVERED', value: summary.value.delivered },
  { key: 'READ', value: summary.value.read },
  { key: 'FAILED', value: summary.value.failed },
  { key: 'SUCCESS_RATE', value: `${summary.value.success_rate}%` },
]);

const statusLabel = status =>
  t(`CAMPAIGN.WHATSAPP.REPORT.STATUS.${STATUS_LABELS[status] ?? 'SENT'}`);

const statusClass = status =>
  ({
    failed: 'bg-n-ruby-3 text-n-ruby-11',
    read: 'bg-n-teal-3 text-n-teal-11',
    delivered: 'bg-n-teal-3 text-n-teal-11',
  })[status] ?? 'bg-n-alpha-2 text-n-slate-11';

const formatDate = timestamp =>
  timestamp ? new Date(timestamp * 1000).toLocaleString('pt-BR') : '—';

// Deep link straight to the message inside the conversation, which is how the
// operator checks what the contact actually got.
const conversationUrl = row =>
  frontendURL(
    `accounts/${accountId.value}/conversations/${row.conversation_id}?messageId=${row.id}`
  );

const goBack = () =>
  router.push({ name: 'campaigns_whatsapp_index', params: route.params });
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto flex flex-col gap-6">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP.REPORT.TITLE') }}
        </h1>
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :label="t('CAMPAIGN.WHATSAPP.REPORT.BACK')"
          @click="goBack"
        />
      </div>

      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>

      <CampaignCard
        v-if="campaign"
        :title="campaign.title"
        :message="campaign.message"
        :status="campaign.campaign_status"
        :sender="campaign.sender"
        :inbox="campaign.inbox"
        :scheduled-at="campaign.scheduled_at"
        :template-params="campaign.template_params"
        :audience="campaign.audience"
        :audience-file-name="campaign.audience_file_name"
        :cadence-seconds="campaign.cadence_seconds"
        :conversation-label="campaign.conversation_label"
        hide-actions
      />

      <div class="grid grid-cols-2 gap-3 md:grid-cols-6">
        <div
          v-for="item in bigNumbers"
          :key="item.key"
          class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">
            {{ t(`CAMPAIGN.WHATSAPP.REPORT.SUMMARY.${item.key}`) }}
          </span>
          <div class="flex items-center gap-2">
            <span class="text-xl font-medium text-n-slate-12">
              {{ item.value }}
            </span>
            <!-- Same "opens" mark as the funnel conversion report. -->
            <button
              v-if="item.key === 'FAILED' && summary.failed > 0"
              v-tooltip.top="t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.OPEN')"
              type="button"
              class="!p-0 text-n-slate-11 hover:text-n-slate-12"
              :aria-label="t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.OPEN')"
              @click="showFailures = true"
            >
              <span class="i-lucide-square-arrow-out-up-right size-4 block" />
            </button>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <input
          v-model="searchQuery"
          type="search"
          :placeholder="t('CAMPAIGN.WHATSAPP.REPORT.SEARCH_PLACEHOLDER')"
          class="!mb-0 w-80 max-w-full h-9 rounded-lg px-3 text-sm"
        />
        <Select v-model="statusFilter" :options="statusOptions" />
      </div>

      <p v-if="isLoading" class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.REPORT.LOADING') }}
      </p>
      <p v-else-if="!messages.length" class="text-sm text-n-slate-11">
        {{
          isFiltering
            ? t('CAMPAIGN.WHATSAPP.REPORT.NO_RESULTS')
            : t('CAMPAIGN.WHATSAPP.REPORT.EMPTY')
        }}
      </p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr
            class="text-left text-xs uppercase text-n-slate-11 border-b border-n-weak"
          >
            <th class="py-2">{{ t('CAMPAIGN.WHATSAPP.REPORT.CONTACT') }}</th>
            <th class="py-2">
              {{ t('CAMPAIGN.WHATSAPP.REPORT.STATUS_COLUMN') }}
            </th>
            <th class="py-2">{{ t('CAMPAIGN.WHATSAPP.REPORT.SENT_AT') }}</th>
            <th class="py-2 text-right">
              {{ t('CAMPAIGN.WHATSAPP.REPORT.CONVERSATION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in messages"
            :key="row.id"
            class="align-top border-b border-n-weak/50"
          >
            <td class="py-2">
              <div class="text-n-slate-12">{{ row.contact_name }}</div>
              <div class="text-xs text-n-slate-11">{{ row.contact_phone }}</div>
            </td>
            <td class="py-2">
              <span
                class="px-2 py-1 text-xs rounded"
                :class="statusClass(row.status)"
              >
                {{ statusLabel(row.status) }}
              </span>
              <div v-if="row.error" class="mt-1 text-xs text-n-ruby-11">
                {{ row.error }}
              </div>
            </td>
            <td class="py-2 text-n-slate-11">
              {{ formatDate(row.sent_at ?? row.created_at) }}
            </td>
            <td class="py-2 text-right">
              <a
                v-if="row.conversation_id"
                :href="conversationUrl(row)"
                class="text-n-blue-text"
              >
                {{ t('CAMPAIGN.WHATSAPP.REPORT.OPEN_CONVERSATION') }}
              </a>
            </td>
          </tr>
        </tbody>
      </table>

      <PaginationFooter
        v-if="meta.total_count > (meta.per_page || 25)"
        :current-page="meta.current_page"
        :total-items="meta.total_count"
        :items-per-page="meta.per_page || 25"
        class="!px-0"
        @update:current-page="fetchPage"
      />
    </div>

    <woot-modal
      v-model:show="showFailures"
      :on-close="() => (showFailures = false)"
    >
      <div class="flex flex-col gap-4 p-6">
        <woot-modal-header
          :header-title="t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.TITLE')"
          :header-content="t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.SUBTITLE')"
        />
        <table class="w-full text-sm">
          <thead>
            <tr
              class="text-left text-xs text-n-slate-11 border-b border-n-weak"
            >
              <th class="py-2">
                {{ t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.ERROR') }}
              </th>
              <th class="py-2 text-right">
                {{ t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.COUNT') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="reason in failureReasons"
              :key="reason.error || 'unknown'"
              class="border-b border-n-weak/50"
            >
              <td class="py-2 pr-4 text-n-slate-12">
                {{
                  reason.error || t('CAMPAIGN.WHATSAPP.REPORT.FAILURES.UNKNOWN')
                }}
              </td>
              <td class="py-2 text-right tabular-nums text-n-slate-12">
                {{ reason.count }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </woot-modal>
  </section>
</template>
