<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MarketingIntegrationsAPI from 'dashboard/api/marketingIntegrations';

// The Meta pixels the account's conversions go to. Every pixel in test mode
// or active gets each conversion, with its own access token; the token is
// write-only, so editing a pixel with the token blank keeps the stored one.
const props = defineProps({
  integrationId: { type: Number, default: null },
  // Creates the Meta integration when the first pixel is added.
  resolveIntegrationId: { type: Function, required: true },
});

const STATUSES = ['disabled', 'test_mode', 'active'];
const STATUS_CLASSES = {
  disabled: 'bg-n-alpha-2 text-n-slate-11',
  test_mode: 'bg-n-amber-3 text-n-amber-11',
  active: 'bg-n-teal-3 text-n-teal-11',
};

const { t } = useI18n();
const rows = ref([]);
const loading = ref(false);
const editingId = ref(null);
const isFormOpen = ref(false);
const isSubmitting = ref(false);
const formError = ref('');
const form = reactive({
  name: '',
  pixel_id: '',
  access_token: '',
  test_event_code: '',
  status: 'test_mode',
});

const editingRow = computed(() =>
  rows.value.find(row => row.id === editingId.value)
);
const canSave = computed(
  () =>
    form.name.trim() &&
    form.pixel_id.trim() &&
    (form.access_token.trim() || editingRow.value?.access_token_set)
);

const statusLabel = status =>
  ({
    disabled: t('MARKETING_ANALYTICS.STATUSES.DISABLED'),
    test_mode: t('MARKETING_ANALYTICS.STATUSES.TEST_MODE'),
    active: t('MARKETING_ANALYTICS.STATUSES.ACTIVE'),
  })[status];

const fetchRows = async () => {
  if (!props.integrationId) {
    rows.value = [];
    return;
  }
  loading.value = true;
  try {
    const { data } = await MarketingIntegrationsAPI.getPixels(
      props.integrationId
    );
    rows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

const openForm = row => {
  editingId.value = row?.id || null;
  Object.assign(form, {
    name: row?.name || '',
    pixel_id: row?.pixel_id || '',
    access_token: '',
    test_event_code: row?.test_event_code || '',
    status: row?.status || 'test_mode',
  });
  formError.value = '';
  isFormOpen.value = true;
};

const closeForm = () => {
  isFormOpen.value = false;
  editingId.value = null;
};

const save = async () => {
  if (!canSave.value) return;
  isSubmitting.value = true;
  formError.value = '';
  try {
    const integrationId = await props.resolveIntegrationId();
    if (editingId.value) {
      await MarketingIntegrationsAPI.updatePixel(
        integrationId,
        editingId.value,
        { ...form }
      );
    } else {
      await MarketingIntegrationsAPI.addPixel(integrationId, { ...form });
    }
    useAlert(t('MARKETING_ANALYTICS.PIXELS.SAVED'));
    closeForm();
    await fetchRows();
  } catch (error) {
    formError.value =
      error.response?.data?.message || t('MARKETING_ANALYTICS.SAVE_ERROR');
  } finally {
    isSubmitting.value = false;
  }
};

const changeStatus = async (row, status) => {
  await MarketingIntegrationsAPI.updatePixel(props.integrationId, row.id, {
    status,
  });
  await fetchRows();
};

const removePixel = async row => {
  if (
    !window.confirm(
      t('MARKETING_ANALYTICS.PIXELS.REMOVE_CONFIRM', { name: row.name })
    )
  )
    return;
  await MarketingIntegrationsAPI.removePixel(props.integrationId, row.id);
  await fetchRows();
};

watch(() => props.integrationId, fetchRows, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-start justify-between gap-4">
      <div>
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('MARKETING_ANALYTICS.PIXELS.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-11 mt-1">
          {{ t('MARKETING_ANALYTICS.PIXELS.DESCRIPTION') }}
        </p>
      </div>
      <Button
        type="button"
        size="sm"
        color="blue"
        icon="i-lucide-plus"
        class="shrink-0"
        :disabled="isFormOpen"
        :label="t('MARKETING_ANALYTICS.PIXELS.ADD')"
        @click="openForm()"
      />
    </div>

    <form
      v-if="isFormOpen"
      class="grid grid-cols-1 gap-3 rounded-lg bg-n-alpha-1 p-3 md:grid-cols-2"
      @submit.prevent="save"
    >
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">
          {{ t('MARKETING_ANALYTICS.PIXELS.NAME') }}
          <span class="text-n-ruby-10">*</span>
        </span>
        <input
          v-model="form.name"
          type="text"
          :placeholder="t('MARKETING_ANALYTICS.PIXELS.NAME_PLACEHOLDER')"
          class="!mb-0 rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">
          {{ t('MARKETING_ANALYTICS.FIELDS.PIXEL_ID') }}
          <span class="text-n-ruby-10">*</span>
        </span>
        <input
          v-model="form.pixel_id"
          type="text"
          inputmode="numeric"
          class="!mb-0 rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">
          {{ t('MARKETING_ANALYTICS.FIELDS.ACCESS_TOKEN') }}
          <span class="text-n-ruby-10">*</span>
        </span>
        <input
          v-model="form.access_token"
          type="password"
          autocomplete="new-password"
          :placeholder="editingRow?.access_token_set ? '••••••••••••' : ''"
          class="!mb-0 rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
        />
        <span
          v-if="editingRow?.access_token_set"
          class="text-xs text-n-slate-10"
        >
          {{ t('MARKETING_ANALYTICS.PIXELS.TOKEN_KEEP_HINT') }}
        </span>
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">
          {{ t('MARKETING_ANALYTICS.FIELDS.TEST_EVENT_CODE') }}
        </span>
        <input
          v-model="form.test_event_code"
          type="text"
          class="!mb-0 rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="text-n-slate-11">{{
          t('MARKETING_ANALYTICS.STATUS')
        }}</span>
        <select
          v-model="form.status"
          class="!mb-0 rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
        >
          <option v-for="status in STATUSES" :key="status" :value="status">
            {{ statusLabel(status) }}
          </option>
        </select>
      </label>
      <div class="flex items-end justify-end gap-2">
        <Button
          type="button"
          size="sm"
          variant="faded"
          color="slate"
          :label="t('MARKETING_ANALYTICS.CANCEL')"
          @click="closeForm"
        />
        <Button
          type="submit"
          size="sm"
          color="blue"
          :disabled="isSubmitting || !canSave"
          :label="t('MARKETING_ANALYTICS.SAVE')"
        />
      </div>
      <p v-if="formError" class="col-span-full mb-0 text-xs text-n-ruby-11">
        {{ formError }}
      </p>
    </form>

    <div
      v-if="!loading && !rows.length && !isFormOpen"
      class="rounded-lg border border-dashed border-n-strong px-4 py-6 text-center text-sm text-n-slate-11"
    >
      {{ t('MARKETING_ANALYTICS.PIXELS.EMPTY') }}
    </div>

    <div
      v-else-if="rows.length"
      class="overflow-x-auto rounded-lg outline outline-1 outline-n-container"
    >
      <table class="w-full text-sm">
        <thead class="bg-n-slate-2 text-xs text-n-slate-11">
          <tr>
            <th class="px-3 py-2 text-left font-medium">
              {{ t('MARKETING_ANALYTICS.PIXELS.COLUMNS.PIXEL') }}
            </th>
            <th class="px-3 py-2 text-left font-medium">
              {{ t('MARKETING_ANALYTICS.FIELDS.TEST_EVENT_CODE') }}
            </th>
            <th class="px-3 py-2 text-left font-medium">
              {{ t('MARKETING_ANALYTICS.STATUS') }}
            </th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak text-n-slate-12">
          <tr v-for="row in rows" :key="row.id" class="align-middle">
            <td class="px-3 py-2">
              <div class="font-medium">{{ row.name }}</div>
              <div class="text-xs text-n-slate-11 font-mono">
                {{ row.pixel_id }}
              </div>
            </td>
            <td class="px-3 py-2 text-xs text-n-slate-11 font-mono">
              {{ row.test_event_code || '—' }}
            </td>
            <td class="px-3 py-2">
              <select
                :value="row.status"
                :aria-label="t('MARKETING_ANALYTICS.STATUS')"
                class="!mb-0 !h-7 rounded-full border-0 py-0 pl-2 pr-7 text-xs font-medium"
                :class="STATUS_CLASSES[row.status]"
                @change="changeStatus(row, $event.target.value)"
              >
                <option
                  v-for="status in STATUSES"
                  :key="status"
                  :value="status"
                >
                  {{ statusLabel(status) }}
                </option>
              </select>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-3">
                <button
                  type="button"
                  class="!p-0 text-n-slate-11 hover:text-n-slate-12"
                  :title="t('MARKETING_ANALYTICS.EDIT')"
                  @click="openForm(row)"
                >
                  <Icon icon="i-lucide-pencil" class="size-4" />
                </button>
                <button
                  type="button"
                  class="!p-0 text-n-slate-11 hover:text-n-ruby-11"
                  :title="t('MARKETING_ANALYTICS.PIXELS.REMOVE')"
                  @click="removePixel(row)"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
