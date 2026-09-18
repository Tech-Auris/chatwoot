<script setup>
// Both provider forms sit here side by side. Reactive form state is loaded
// from the store on mount; the CTA sends only the fields the operator
// touched, so leaving a secret input blank preserves what's stored (the
// backend does a merge on PATCH — see PR #561).
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const STATUSES = ['disabled', 'test_mode', 'active'];
const META_CAPI_FIELDS = [
  { key: 'pixel_id', secret: false, required: true },
  { key: 'access_token', secret: true, required: true },
  { key: 'test_event_code', secret: false, required: false },
];
const GOOGLE_ADS_FIELDS = [
  { key: 'customer_id', secret: false, required: true },
  { key: 'conversion_action_id', secret: false, required: true },
  { key: 'developer_token', secret: true, required: true },
  { key: 'oauth_refresh_token', secret: true, required: true },
  { key: 'login_customer_id', secret: false, required: false },
];

const { t } = useI18n();
const store = useStore();
const integrations = useMapGetter(
  'marketingIntegrations/getMarketingIntegrations'
);
const uiFlags = useMapGetter('marketingIntegrations/getUIFlags');

const findByProvider = provider =>
  integrations.value.find(record => record.provider === provider) || null;

const forms = reactive({
  meta_capi: { status: 'test_mode', credentials: {} },
  google_ads_enhanced: { status: 'test_mode', credentials: {} },
});
const dirtyCredentials = reactive({
  meta_capi: {},
  google_ads_enhanced: {},
});
const savingProvider = ref(null);

const isSaving = provider =>
  savingProvider.value === provider &&
  (uiFlags.value.isCreating || uiFlags.value.isUpdating);

const syncForm = provider => {
  const record = findByProvider(provider);
  forms[provider].status = record?.status || 'test_mode';
  forms[provider].credentials = { ...(record?.credentials || {}) };
  dirtyCredentials[provider] = {};
};

const credentialsSetFor = provider =>
  findByProvider(provider)?.credentials_set || {};

const bindCredential = (provider, key) => ({
  onInput: event => {
    forms[provider].credentials[key] = event.target.value;
    dirtyCredentials[provider][key] = true;
  },
});

const placeholderFor = (provider, field) => {
  if (!field.secret) return '';
  return credentialsSetFor(provider)[field.key] ? '••••••••••••' : '';
};

const displayValue = (provider, field) => {
  if (field.secret && !dirtyCredentials[provider][field.key]) return '';
  return forms[provider].credentials[field.key] ?? '';
};

const isFormValid = provider => {
  const record = findByProvider(provider);
  const fields =
    provider === 'meta_capi' ? META_CAPI_FIELDS : GOOGLE_ADS_FIELDS;
  return fields.every(field => {
    if (!field.required) return true;
    const typedValue = forms[provider].credentials[field.key];
    if (typedValue) return true;
    // The secret is stored server-side; the operator does not need to
    // re-type it to keep the record valid.
    return field.secret && record?.credentials_set?.[field.key];
  });
};

const saveIntegration = async provider => {
  savingProvider.value = provider;
  const record = findByProvider(provider);
  const payload = { status: forms[provider].status };
  const touched = {};
  Object.keys(dirtyCredentials[provider]).forEach(key => {
    touched[key] = forms[provider].credentials[key] ?? '';
  });
  // Always send the non-secret keys — they are cheap to round-trip and let
  // the operator clear a field by blanking it out.
  const fields =
    provider === 'meta_capi' ? META_CAPI_FIELDS : GOOGLE_ADS_FIELDS;
  fields
    .filter(field => !field.secret)
    .forEach(field => {
      touched[field.key] = forms[provider].credentials[field.key] ?? '';
    });
  payload.credentials = touched;

  try {
    if (record) {
      await store.dispatch('marketingIntegrations/update', {
        id: record.id,
        ...payload,
      });
    } else {
      await store.dispatch('marketingIntegrations/create', {
        provider,
        ...payload,
      });
    }
    useAlert(t('MARKETING_ANALYTICS.SAVE_SUCCESS'));
    syncForm(provider);
  } catch (error) {
    useAlert(error?.message || t('MARKETING_ANALYTICS.SAVE_ERROR'));
  } finally {
    savingProvider.value = null;
  }
};

const disconnect = async provider => {
  const record = findByProvider(provider);
  if (!record) return;
  if (!window.confirm(t('MARKETING_ANALYTICS.DISCONNECT_CONFIRM'))) return;
  try {
    await store.dispatch('marketingIntegrations/delete', record.id);
    useAlert(t('MARKETING_ANALYTICS.DISCONNECT_SUCCESS'));
    syncForm(provider);
  } catch (error) {
    useAlert(error?.message || t('MARKETING_ANALYTICS.SAVE_ERROR'));
  }
};

onMounted(async () => {
  await store.dispatch('marketingIntegrations/get');
  syncForm('meta_capi');
  syncForm('google_ads_enhanced');
});

watch(integrations, () => {
  syncForm('meta_capi');
  syncForm('google_ads_enhanced');
});

const providers = computed(() => [
  { key: 'meta_capi', label: 'Meta CAPI', fields: META_CAPI_FIELDS },
  {
    key: 'google_ads_enhanced',
    label: 'Google Ads Enhanced Conversions',
    fields: GOOGLE_ADS_FIELDS,
  },
]);
</script>

<template>
  <div class="flex flex-col gap-6">
    <section
      v-for="provider in providers"
      :key="provider.key"
      class="rounded-lg border border-n-strong bg-n-solid-1 p-6"
    >
      <header class="flex items-start justify-between gap-4 mb-4">
        <div>
          <h3 class="text-base font-medium text-n-slate-12">
            {{ provider.label }}
          </h3>
          <p class="text-sm text-n-slate-11 mt-1">
            {{
              t(
                `MARKETING_ANALYTICS.PROVIDERS.${provider.key.toUpperCase()}.DESCRIPTION`
              )
            }}
          </p>
        </div>
        <button
          v-if="findByProvider(provider.key)"
          type="button"
          class="text-xs text-n-ruby-10 hover:underline"
          @click="disconnect(provider.key)"
        >
          {{ t('MARKETING_ANALYTICS.DISCONNECT') }}
        </button>
      </header>

      <form
        class="grid grid-cols-1 md:grid-cols-2 gap-4"
        @submit.prevent="saveIntegration(provider.key)"
      >
        <label class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">{{
            t('MARKETING_ANALYTICS.STATUS')
          }}</span>
          <select
            v-model="forms[provider.key].status"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
          >
            <option v-for="status in STATUSES" :key="status" :value="status">
              {{ t(`MARKETING_ANALYTICS.STATUSES.${status.toUpperCase()}`) }}
            </option>
          </select>
        </label>

        <label
          v-for="field in provider.fields"
          :key="field.key"
          class="flex flex-col gap-1 text-sm"
        >
          <span class="text-n-slate-11">
            {{ t(`MARKETING_ANALYTICS.FIELDS.${field.key.toUpperCase()}`) }}
            <span v-if="field.required" class="text-n-ruby-10">*</span>
          </span>
          <input
            :type="field.secret ? 'password' : 'text'"
            :value="displayValue(provider.key, field)"
            :placeholder="placeholderFor(provider.key, field)"
            class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-n-slate-12"
            @input="bindCredential(provider.key, field.key).onInput($event)"
          />
        </label>

        <div class="col-span-full flex justify-end">
          <button
            type="submit"
            :disabled="isSaving(provider.key) || !isFormValid(provider.key)"
            class="rounded bg-n-brand hover:bg-n-brand/90 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-50"
          >
            {{
              findByProvider(provider.key)
                ? t('MARKETING_ANALYTICS.SAVE')
                : t('MARKETING_ANALYTICS.CONNECT')
            }}
          </button>
        </div>
      </form>
    </section>
  </div>
</template>
