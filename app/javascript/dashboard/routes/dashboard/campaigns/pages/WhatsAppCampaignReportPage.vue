<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CampaignsAPI from 'dashboard/api/campaigns';
import Button from 'dashboard/components-next/button/Button.vue';
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
const messages = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
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
    const { data } = await CampaignsAPI.report(campaignId.value, page);
    summary.value = data.summary ?? summary.value;
    messages.value = data.messages ?? [];
    meta.value = data.meta ?? meta.value;
  } catch {
    error.value = t('CAMPAIGN.WHATSAPP.REPORT.ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => fetchPage(1));

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
  messages.value = [];
  meta.value = { current_page: 1, total_pages: 1, total_count: 0 };
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

      <div class="grid grid-cols-2 gap-3 md:grid-cols-6">
        <div
          v-for="item in bigNumbers"
          :key="item.key"
          class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">
            {{ t(`CAMPAIGN.WHATSAPP.REPORT.SUMMARY.${item.key}`) }}
          </span>
          <span class="text-xl font-medium text-n-slate-12">
            {{ item.value }}
          </span>
        </div>
      </div>

      <p v-if="isLoading" class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.REPORT.LOADING') }}
      </p>
      <p v-else-if="!messages.length" class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.REPORT.EMPTY') }}
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

      <div v-if="meta.total_pages > 1" class="flex items-center gap-3 text-sm">
        <button
          type="button"
          class="text-n-blue-text disabled:opacity-40"
          :disabled="meta.current_page <= 1"
          @click="fetchPage(meta.current_page - 1)"
        >
          {{ t('CAMPAIGN.WHATSAPP.REPORT.PREVIOUS') }}
        </button>
        <span class="text-n-slate-11">
          {{
            t('CAMPAIGN.WHATSAPP.REPORT.PAGE', {
              current: meta.current_page,
              total: meta.total_pages,
            })
          }}
        </span>
        <button
          type="button"
          class="text-n-blue-text disabled:opacity-40"
          :disabled="meta.current_page >= meta.total_pages"
          @click="fetchPage(meta.current_page + 1)"
        >
          {{ t('CAMPAIGN.WHATSAPP.REPORT.NEXT') }}
        </button>
      </div>
    </div>
  </section>
</template>
