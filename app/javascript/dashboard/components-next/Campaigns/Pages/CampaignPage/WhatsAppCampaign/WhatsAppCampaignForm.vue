<script setup>
import { reactive, computed, watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, requiredIf, minLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';
import CampaignsAPI from 'dashboard/api/campaigns';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const formState = {
  uiFlags: useMapGetter('campaigns/getUIFlags'),
  labels: useMapGetter('labels/getLabels'),
  inboxes: useMapGetter('inboxes/getWhatsAppInboxes'),
  getFilteredWhatsAppTemplates: useMapGetter(
    'inboxes/getFilteredWhatsAppTemplates'
  ),
};

const initialState = {
  title: '',
  inboxId: null,
  templateId: null,
  scheduledAt: null,
  selectedAudience: [],
  cadenceUnit: 'seconds',
  cadenceValue: 10,
  audienceSource: 'labels',
  audienceContactIds: [],
  shouldLabelConversations: false,
  conversationLabel: null,
};

// Messages go out spaced by this interval instead of all at once. The floor of
// 10s mirrors the backend validation.
const CADENCE_OPTIONS = {
  seconds: [10, 15, 30],
  minutes: [1, 2, 5],
};

const state = reactive({ ...initialState });

const AUDIENCE_SAMPLE_CSV = '/downloads/campaign-audience-sample.csv';

const csvFileName = ref('');
const csvSummary = ref(null);
const csvError = ref('');
const isImportingCsv = ref(false);
const templateParserRef = ref(null);

const rules = {
  title: { required, minLength: minLength(1) },
  inboxId: { required },
  templateId: { required },
  scheduledAt: { required },
  // Only the source in use is required: labels when picking tags, imported
  // contacts when uploading a file.
  selectedAudience: {
    required: requiredIf(() => state.audienceSource === 'labels'),
  },
  audienceContactIds: {
    required: requiredIf(() => state.audienceSource === 'file'),
  },
  cadenceValue: { required },
};

const v$ = useVuelidate(rules, state);

const isCreating = computed(() => formState.uiFlags.value.isCreating);

const currentDateTime = computed(() => {
  // Added to disable the scheduled at field from being set to the current time
  const now = new Date();
  const localTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
});

const mapToOptions = (items, valueKey, labelKey) =>
  items?.map(item => ({
    value: item[valueKey],
    label: item[labelKey],
  })) ?? [];

const audienceList = computed(() =>
  mapToOptions(formState.labels.value, 'id', 'title')
);

const inboxOptions = computed(() =>
  mapToOptions(formState.inboxes.value, 'id', 'name')
);

const templateOptions = computed(() => {
  if (!state.inboxId) return [];
  const templates = formState.getFilteredWhatsAppTemplates.value(state.inboxId);
  return templates.map(template => {
    // Create a more user-friendly label from template name
    const friendlyName = template.name
      .replace(/_/g, ' ')
      .replace(/\b\w/g, l => l.toUpperCase());

    return {
      value: template.id,
      label: `${friendlyName} (${template.language || 'en'})`,
      template: template,
    };
  });
});

const selectedTemplate = computed(() => {
  if (!state.templateId) return null;
  return templateOptions.value.find(option => option.value === state.templateId)
    ?.template;
});

const getErrorMessage = (field, errorKey) => {
  const baseKey = 'CAMPAIGN.WHATSAPP.CREATE.FORM';
  return v$.value[field].$error ? t(`${baseKey}.${errorKey}.ERROR`) : '';
};

const formErrors = computed(() => ({
  title: getErrorMessage('title', 'TITLE'),
  inbox: getErrorMessage('inboxId', 'INBOX'),
  template: getErrorMessage('templateId', 'TEMPLATE'),
  scheduledAt: getErrorMessage('scheduledAt', 'SCHEDULED_AT'),
  audience: getErrorMessage('selectedAudience', 'AUDIENCE'),
}));

const hasRequiredTemplateParams = computed(() => {
  return templateParserRef.value?.v$?.$invalid === false || true;
});

const audienceSourceOptions = computed(() => [
  {
    value: 'labels',
    label: t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_SOURCE.LABELS'),
  },
  {
    value: 'file',
    label: t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_SOURCE.FILE'),
  },
]);

const labelOptions = computed(() =>
  (formState.labels?.value ?? []).map(label => ({
    value: label.title,
    label: label.title,
  }))
);

// The file is turned into contacts before the campaign is created, so the
// operator sees what it produced and can fix the file instead of finding out
// when the campaign fires.
const onCsvSelected = async event => {
  const file = event.target.files?.[0];
  if (!file) return;

  csvFileName.value = file.name;
  csvError.value = '';
  csvSummary.value = null;
  state.audienceContactIds = [];
  isImportingCsv.value = true;

  try {
    const { data } = await CampaignsAPI.importAudience(file);
    state.audienceContactIds = data.contact_ids ?? [];
    csvSummary.value = data;
  } catch (error) {
    csvError.value =
      error?.response?.data?.error ??
      t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.ERROR');
  } finally {
    isImportingCsv.value = false;
  }
};

const audiencePayload = () =>
  state.audienceSource === 'file'
    ? state.audienceContactIds.map(id => ({ id, type: 'Contact' }))
    : state.selectedAudience?.map(id => ({ id, type: 'Label' }));

const cadenceUnitOptions = computed(() => [
  {
    value: 'seconds',
    label: t('CAMPAIGN.WHATSAPP.CREATE.FORM.CADENCE.UNITS.SECONDS'),
  },
  {
    value: 'minutes',
    label: t('CAMPAIGN.WHATSAPP.CREATE.FORM.CADENCE.UNITS.MINUTES'),
  },
]);

const cadenceValues = computed(
  () => CADENCE_OPTIONS[state.cadenceUnit] ?? CADENCE_OPTIONS.seconds
);

const cadenceValueOptions = computed(() =>
  cadenceValues.value.map(value => ({ value, label: String(value) }))
);

const cadenceSeconds = computed(() =>
  state.cadenceUnit === 'minutes'
    ? Number(state.cadenceValue) * 60
    : Number(state.cadenceValue)
);

// Switching the unit keeps the field on a value that exists in the new list.
watch(
  () => state.cadenceUnit,
  () => {
    if (!cadenceValues.value.includes(Number(state.cadenceValue))) {
      state.cadenceValue = cadenceValues.value[0];
    }
  }
);

const isSubmitDisabled = computed(
  () => v$.value.$invalid || !hasRequiredTemplateParams.value
);

const formatToUTCString = localDateTime =>
  localDateTime ? new Date(localDateTime).toISOString() : null;

const resetState = () => {
  Object.assign(state, initialState);
  v$.value.$reset();
};

const handleCancel = () => emit('cancel');

const prepareCampaignDetails = () => {
  // Find the selected template to get its content
  const currentTemplate = selectedTemplate.value;
  const parserData = templateParserRef.value;

  // Extract template content - this should be the template message body
  const templateContent = parserData?.renderedTemplate || '';

  // Prepare template_params object with the same structure as used in contacts
  const templateParams = {
    name: currentTemplate?.name || '',
    namespace: currentTemplate?.namespace || '',
    category: currentTemplate?.category || 'UTILITY',
    language: currentTemplate?.language || 'en_US',
    processed_params: parserData?.processedParams || {},
  };

  return {
    title: state.title,
    message: templateContent,
    template_params: templateParams,
    inbox_id: state.inboxId,
    scheduled_at: formatToUTCString(state.scheduledAt),
    cadence_seconds: cadenceSeconds.value,
    audience: audiencePayload(),
    conversation_label: state.shouldLabelConversations
      ? state.conversationLabel
      : null,
    audience_file_name:
      state.audienceSource === 'file' ? csvFileName.value : null,
  };
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  emit('submit', prepareCampaignDetails());
  resetState();
  handleCancel();
};

// Reset template selection when inbox changes
watch(
  () => state.inboxId,
  () => {
    state.templateId = null;
  }
);
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.title"
      :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TITLE.LABEL')"
      :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TITLE.PLACEHOLDER')"
      :message="formErrors.title"
      :message-type="formErrors.title ? 'error' : 'info'"
    />

    <div class="flex flex-col gap-1">
      <label for="inbox" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.INBOX.LABEL') }}
      </label>
      <ComboBox
        id="inbox"
        v-model="state.inboxId"
        :options="inboxOptions"
        :has-error="!!formErrors.inbox"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.INBOX.PLACEHOLDER')"
        :message="formErrors.inbox"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="template" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.LABEL') }}
      </label>
      <ComboBox
        id="template"
        v-model="state.templateId"
        :options="templateOptions"
        :has-error="!!formErrors.template"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.PLACEHOLDER')"
        :message="formErrors.template"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
      <p class="mt-1 text-xs text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.INFO') }}
      </p>
    </div>

    <!-- Template Parser -->
    <WhatsAppTemplateParser
      v-if="selectedTemplate"
      ref="templateParserRef"
      :template="selectedTemplate"
    />

    <div class="flex flex-col gap-1">
      <label
        for="audience-source"
        class="mb-0.5 text-sm font-medium text-n-slate-12"
      >
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_SOURCE.LABEL') }}
      </label>
      <ComboBox
        id="audience-source"
        v-model="state.audienceSource"
        :options="audienceSourceOptions"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <div v-if="state.audienceSource === 'labels'" class="flex flex-col gap-1">
      <label for="audience" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL') }}
      </label>
      <TagMultiSelectComboBox
        v-model="state.selectedAudience"
        :options="audienceList"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL')"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.PLACEHOLDER')"
        :has-error="!!formErrors.audience"
        :message="formErrors.audience"
        class="[&>div>button]:bg-n-alpha-black2"
      />
    </div>

    <div v-else class="flex flex-col gap-1">
      <label
        for="audience-file"
        class="mb-0.5 text-sm font-medium text-n-slate-12"
      >
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.LABEL') }}
      </label>
      <p class="mb-1 text-xs text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.INFO') }}
        <a
          :href="AUDIENCE_SAMPLE_CSV"
          download="campaign-audience-sample.csv"
          class="text-n-blue-text"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.SAMPLE') }}
        </a>
      </p>
      <input
        id="audience-file"
        type="file"
        accept=".csv,text/csv"
        class="text-sm text-n-slate-12 file:mr-3 file:rounded-lg file:border-0 file:bg-n-alpha-2 file:px-3 file:py-1.5 file:text-sm file:text-n-slate-12"
        @change="onCsvSelected"
      />
      <p v-if="isImportingCsv" class="mt-1 text-xs text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.IMPORTING') }}
      </p>
      <p v-else-if="csvError" class="mt-1 text-xs text-n-ruby-11">
        {{ csvError }}
      </p>
      <p v-else-if="csvSummary" class="mt-1 text-xs text-n-slate-11">
        {{
          t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.SUMMARY', {
            total: state.audienceContactIds.length,
            created: csvSummary.created_count,
            reused: csvSummary.reused_count,
          })
        }}
        <span v-if="csvSummary.invalid_rows?.length" class="text-n-ruby-11">
          {{
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_FILE.INVALID', {
              count: csvSummary.invalid_rows.length,
            })
          }}
        </span>
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <label
        class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
      >
        <input v-model="state.shouldLabelConversations" type="checkbox" />
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CONVERSATION_LABEL.TOGGLE') }}
      </label>
      <ComboBox
        v-if="state.shouldLabelConversations"
        id="conversation-label"
        v-model="state.conversationLabel"
        :options="labelOptions"
        :placeholder="
          t('CAMPAIGN.WHATSAPP.CREATE.FORM.CONVERSATION_LABEL.PLACEHOLDER')
        "
        class="mt-1 [&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="cadence" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CADENCE.LABEL') }}
      </label>
      <div class="flex gap-2">
        <ComboBox
          id="cadence-unit"
          v-model="state.cadenceUnit"
          :options="cadenceUnitOptions"
          class="w-1/2 [&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        />
        <ComboBox
          id="cadence-value"
          v-model="state.cadenceValue"
          :options="cadenceValueOptions"
          class="w-1/2 [&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        />
      </div>
      <p class="mt-1 text-xs text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CADENCE.INFO') }}
      </p>
    </div>

    <Input
      v-model="state.scheduledAt"
      :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SCHEDULED_AT.LABEL')"
      type="datetime-local"
      :min="currentDateTime"
      :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SCHEDULED_AT.PLACEHOLDER')"
      :message="formErrors.scheduledAt"
      :message-type="formErrors.scheduledAt ? 'error' : 'info'"
    />

    <div class="flex gap-3 justify-between items-center w-full">
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CREATE')"
        class="w-full"
        type="submit"
        :is-loading="isCreating"
        :disabled="isCreating || isSubmitDisabled"
      />
    </div>
  </form>
</template>
