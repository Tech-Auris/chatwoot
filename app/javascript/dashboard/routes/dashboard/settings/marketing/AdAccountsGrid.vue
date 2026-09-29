<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MarketingIntegrationsAPI from 'dashboard/api/marketingIntegrations';

// Meta ad accounts whose spend feeds Gasto / CPL / CPA / ROAS. Added one by
// one: the server checks each with Meta before saving, so an account the
// token can't read is reported right here instead of as an empty report.
const props = defineProps({
  integrationId: { type: Number, required: true },
});

const { t } = useI18n();

// Give the queued sync a moment before reading the outcome back.
const SYNC_REFRESH_DELAY_MS = 8000;

const rows = ref([]);
const loading = ref(false);
const isAdding = ref(false);
const newExternalId = ref('');
const addError = ref('');
const isSubmitting = ref(false);
const isSyncing = ref(false);

const fetchRows = async () => {
  loading.value = true;
  try {
    const { data } = await MarketingIntegrationsAPI.getAdAccounts(
      props.integrationId
    );
    rows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

const startAdding = () => {
  isAdding.value = true;
  newExternalId.value = '';
  addError.value = '';
};

const cancelAdding = () => {
  isAdding.value = false;
  addError.value = '';
};

const addAccount = async () => {
  if (!newExternalId.value.trim()) return;
  isSubmitting.value = true;
  addError.value = '';
  try {
    await MarketingIntegrationsAPI.addAdAccount(
      props.integrationId,
      newExternalId.value.trim()
    );
    isAdding.value = false;
    useAlert(t('MARKETING_ANALYTICS.AD_ACCOUNTS.ADDED'));
    await fetchRows();
  } catch (error) {
    addError.value =
      error.response?.data?.error ||
      t('MARKETING_ANALYTICS.AD_ACCOUNTS.ADD_FAILED');
  } finally {
    isSubmitting.value = false;
  }
};

const toggleEnabled = async row => {
  await MarketingIntegrationsAPI.updateAdAccount(props.integrationId, row.id, {
    enabled: !row.enabled,
  });
  await fetchRows();
};

const removeAccount = async row => {
  await MarketingIntegrationsAPI.removeAdAccount(props.integrationId, row.id);
  await fetchRows();
};

const syncNow = async () => {
  isSyncing.value = true;
  try {
    await MarketingIntegrationsAPI.syncAdAccounts(props.integrationId);
    useAlert(t('MARKETING_ANALYTICS.AD_ACCOUNTS.SYNC_STARTED'));
    setTimeout(async () => {
      await fetchRows();
      isSyncing.value = false;
    }, SYNC_REFRESH_DELAY_MS);
  } catch {
    isSyncing.value = false;
  }
};

const formatDateTime = unix =>
  new Date(unix * 1000).toLocaleString(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  });

onMounted(fetchRows);
</script>

<template>
  <div class="col-span-full flex flex-col gap-3 pt-4 border-t border-n-weak">
    <div class="flex items-start justify-between gap-4">
      <div>
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-11 mt-1">
          {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex items-center gap-2 shrink-0">
        <button
          type="button"
          :disabled="isSyncing || !rows.length"
          class="rounded border border-n-strong px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
          @click="syncNow"
        >
          {{
            isSyncing
              ? t('MARKETING_ANALYTICS.AD_ACCOUNTS.SYNCING')
              : t('MARKETING_ANALYTICS.AD_ACCOUNTS.SYNC_NOW')
          }}
        </button>
        <button
          type="button"
          :disabled="isAdding"
          class="inline-flex items-center gap-1 rounded bg-n-brand hover:bg-n-brand/90 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-50"
          @click="startAdding"
        >
          <Icon icon="i-lucide-plus" class="size-4" />
          {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.ADD') }}
        </button>
      </div>
    </div>

    <div
      v-if="isAdding"
      class="flex flex-col gap-2 rounded-lg bg-n-alpha-1 p-3"
    >
      <div class="flex flex-col gap-2 sm:flex-row">
        <input
          v-model="newExternalId"
          type="text"
          :placeholder="t('MARKETING_ANALYTICS.AD_ACCOUNTS.ID_PLACEHOLDER')"
          class="flex-1 rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-sm text-n-slate-12"
          @keydown.enter.prevent="addAccount"
        />
        <div class="flex gap-2">
          <button
            type="button"
            :disabled="isSubmitting || !newExternalId.trim()"
            class="rounded bg-n-brand hover:bg-n-brand/90 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-50"
            @click="addAccount"
          >
            {{
              isSubmitting
                ? t('MARKETING_ANALYTICS.AD_ACCOUNTS.CHECKING')
                : t('MARKETING_ANALYTICS.AD_ACCOUNTS.CONFIRM_ADD')
            }}
          </button>
          <button
            type="button"
            class="rounded border border-n-strong px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="cancelAdding"
          >
            {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.CANCEL') }}
          </button>
        </div>
      </div>
      <p class="text-xs text-n-slate-10">
        {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.ID_HINT') }}
      </p>
      <p v-if="addError" class="text-xs text-n-ruby-11">{{ addError }}</p>
    </div>

    <div
      v-if="!loading && !rows.length && !isAdding"
      class="rounded-lg border border-dashed border-n-strong px-4 py-6 text-center text-sm text-n-slate-11"
    >
      {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.EMPTY') }}
    </div>

    <div
      v-else-if="rows.length"
      class="overflow-x-auto rounded-lg outline outline-1 outline-n-container"
    >
      <table class="w-full text-sm">
        <thead class="bg-n-slate-2 text-xs text-n-slate-11">
          <tr>
            <th class="px-3 py-2 text-left font-medium">
              {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.COLUMNS.ACCOUNT') }}
            </th>
            <th class="px-3 py-2 text-left font-medium">
              {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.COLUMNS.LAST_SYNC') }}
            </th>
            <th class="px-3 py-2 text-left font-medium">
              {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.COLUMNS.ACTIVE') }}
            </th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak text-n-slate-12">
          <tr v-for="row in rows" :key="row.id" class="align-top">
            <td class="px-3 py-2">
              <div class="font-medium">
                {{ row.name || t('MARKETING_ANALYTICS.AD_ACCOUNTS.NO_NAME') }}
              </div>
              <div class="text-xs text-n-slate-11 font-mono">
                {{
                  t('MARKETING_ANALYTICS.AD_ACCOUNTS.ACT_ID', {
                    id: row.external_id,
                  })
                }}
                <span v-if="row.currency">{{
                  t('MARKETING_ANALYTICS.AD_ACCOUNTS.CURRENCY', {
                    currency: row.currency,
                  })
                }}</span>
              </div>
            </td>
            <td class="px-3 py-2">
              <span
                v-if="row.last_sync_status === 'ok'"
                class="inline-flex rounded-full bg-n-teal-3 px-2 py-0.5 text-xs text-n-teal-12"
              >
                {{
                  t('MARKETING_ANALYTICS.AD_ACCOUNTS.SYNC_OK', {
                    date: formatDateTime(row.last_synced_at),
                    rows: row.last_rows_synced,
                  })
                }}
              </span>
              <div v-else-if="row.last_sync_status === 'error'">
                <span
                  class="inline-flex rounded-full bg-n-ruby-3 px-2 py-0.5 text-xs text-n-ruby-12"
                >
                  {{
                    t('MARKETING_ANALYTICS.AD_ACCOUNTS.SYNC_ERROR', {
                      date: formatDateTime(row.last_synced_at),
                    })
                  }}
                </span>
                <p class="mt-1 mb-0 text-xs text-n-slate-11">
                  {{ row.last_sync_error }}
                </p>
              </div>
              <span v-else class="text-xs text-n-slate-11">
                {{ t('MARKETING_ANALYTICS.AD_ACCOUNTS.SYNC_PENDING') }}
              </span>
            </td>
            <td class="px-3 py-2">
              <input
                type="checkbox"
                :checked="row.enabled"
                class="cursor-pointer"
                @change="toggleEnabled(row)"
              />
            </td>
            <td class="px-3 py-2 text-right">
              <button
                type="button"
                class="text-n-slate-11 hover:text-n-ruby-11"
                :title="t('MARKETING_ANALYTICS.AD_ACCOUNTS.REMOVE')"
                @click="removeAccount(row)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
