<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import TemplatePreview from './TemplatePreview.vue';
import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { useAlert } from 'dashboard/composables';

// Shared form used by both the create (New.vue) and edit (Edit.vue)
// pages. Owns all the state, validation, payload building and the live
// preview panel — the parent only has to wire the submit/cancel events
// and provide inbox context (create) or the existing template (edit).

const props = defineProps({
  // 'create' | 'edit' — controls which fields are locked and which
  // button label we show. Meta rejects edits to name/language/inbox on
  // an existing template, so those become read-only in edit mode.
  mode: {
    type: String,
    default: 'create',
    validator: v => ['create', 'edit'].includes(v),
  },
  // The list of Cloud WhatsApp inboxes the user can target. Only used
  // in create mode.
  inboxes: {
    type: Array,
    default: () => [],
  },
  // In edit mode: the template being edited (shape from GET /meta_templates).
  // We derive the initial form state from it. In create mode this stays null.
  initialTemplate: {
    type: Object,
    default: null,
  },
  // In edit mode: the inbox the template lives on (already resolved by
  // the parent from the URL query). In create mode this stays null and
  // we auto-select the first available inbox.
  initialInboxId: {
    type: [Number, String],
    default: null,
  },
  submitting: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const CATEGORY_OPTIONS = ['MARKETING', 'UTILITY', 'AUTHENTICATION'];
const LANGUAGE_OPTIONS = ['pt_BR', 'en', 'en_US', 'es', 'es_ES'];

// Meta limits (v18+):
//   header TEXT: ≤ 60 chars, ≤ 1 variable
//   body: ≤ 1024 chars, N variables
//   footer: ≤ 60 chars, no variables
//   buttons: ≤ 3 quick_reply OR ≤ 2 URL + ≤ 1 phone
const HEADER_MAX = 60;
const BODY_MAX = 1024;
const FOOTER_MAX = 60;
const QUICK_REPLY_MAX = 3;
const URL_BUTTONS_MAX = 2;
const PHONE_BUTTONS_MAX = 1;
const BUTTON_TEXT_MAX = 25;

const isEdit = computed(() => props.mode === 'edit');

const selectedInboxId = ref(props.initialInboxId ?? null);
const name = ref('');
const language = ref('pt_BR');
const category = ref('UTILITY');

const headerEnabled = ref(false);
// TEXT keeps the existing flow; IMAGE unlocks the file picker path.
// EDIT mode intentionally sticks to TEXT — see comment on
// `hydrateFromTemplate` for why we don't roundtrip IMAGE headers on
// edit (Meta strips omitted components, and re-uploading every time
// would surprise operators). Fatia 3c is create-only for IMAGE.
const HEADER_MEDIA_MAX_BYTES = 5 * 1024 * 1024;
const HEADER_MEDIA_ACCEPTED_TYPES = 'image/jpeg,image/png';
const headerFormat = ref('TEXT');
const headerText = ref('');
const headerSample = ref('');
const headerMediaHandle = ref(null);
const headerMediaPreviewUrl = ref(null);
const headerMediaFileName = ref('');
const headerMediaUploading = ref(false);
const headerFileInput = ref(null);

const bodyText = ref('');
const bodySamples = ref({});

const footerEnabled = ref(false);
const footerText = ref('');

const buttons = ref([]);

// Function declaration (not const) so hydrateFromTemplate below can
// reference it — hoisting lets us keep the reactive setup in reading
// order without a forward-decl shuffle.
//
// Meta supports two placeholder styles: positional ({{1}}, {{2}}) and
// named ({{name}}, {{order_id}}). Both are one-per-template — Meta
// rejects a mix inside the same template body/header. Returns
// { format, vars } so callers can both list slots to fill AND decide
// which shape to send in the create payload (`parameter_format` +
// `body_text_named_params` vs the default positional `body_text`).
const POSITIONAL_VAR_REGEX = /\{\{\s*(\d+)\s*\}\}/g;
const NAMED_VAR_REGEX = /\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g;

function extractVariables(text) {
  const source = text || '';
  const positional = [...source.matchAll(POSITIONAL_VAR_REGEX)].map(m => m[1]);
  const named = [...source.matchAll(NAMED_VAR_REGEX)].map(m => m[1]);

  if (positional.length && named.length) return { format: 'MIXED', vars: [] };
  if (named.length) {
    return { format: 'NAMED', vars: [...new Set(named)] };
  }
  if (positional.length) {
    return {
      format: 'POSITIONAL',
      vars: [...new Set(positional)].sort((a, b) => Number(a) - Number(b)),
    };
  }
  return { format: 'NONE', vars: [] };
}

function detectVariables(text) {
  return extractVariables(text).vars;
}

// Hydrate the form fields from a template pulled off Meta. Runs on
// mount if an initial template was provided, and again whenever the
// parent swaps it (e.g. the operator refreshes the list while the
// edit page is open). Components come back exactly as Meta stored them.
const hydrateFromTemplate = template => {
  if (!template) return;

  name.value = template.name || '';
  language.value = template.language || 'pt_BR';
  category.value = (template.category || 'UTILITY').toUpperCase();

  const components = template.components || [];
  const header = components.find(
    c => (c.type || '').toUpperCase() === 'HEADER'
  );
  const body = components.find(c => (c.type || '').toUpperCase() === 'BODY');
  const footer = components.find(
    c => (c.type || '').toUpperCase() === 'FOOTER'
  );
  const buttonsComp = components.find(
    c => (c.type || '').toUpperCase() === 'BUTTONS'
  );

  // Only TEXT headers hydrate into the form. Non-TEXT (IMAGE/VIDEO/
  // DOCUMENT) stays as-is on Meta and the form doesn't try to edit it —
  // Meta doesn't return a fetchable URL for the current media, so
  // requiring a re-upload silently on edit would break the operator's
  // mental model ("I edited the body, why is my logo gone?"). Skipping
  // hydration for MEDIA headers means the edit payload won't include a
  // HEADER component (see buildPayload) and the current one is preserved.
  const headerFormatOnMeta = (header?.format || 'TEXT').toUpperCase();
  const isTextHeader = headerFormatOnMeta === 'TEXT';
  headerEnabled.value = !!header && isTextHeader;
  headerFormat.value = 'TEXT';
  headerText.value = isTextHeader ? header?.text || '' : '';
  // Header samples come in one of two shapes depending on the template's
  // parameter_format: header_text (positional) OR header_text_named_params
  // (named). Pick whichever matches how the operator authored it.
  if (isTextHeader) {
    const namedHeaderExample =
      header?.example?.header_text_named_params?.[0]?.example;
    headerSample.value =
      namedHeaderExample || header?.example?.header_text?.[0] || '';
  } else {
    headerSample.value = '';
  }

  bodyText.value = body?.text || '';
  bodySamples.value = {};
  // Named-var templates ship samples as [{param_name, example}]; positional
  // ones as [[val1, val2, ...]]. Detect which shape is present and hydrate
  // the sample map keyed by var token so the form re-uses it seamlessly.
  const namedSamples = body?.example?.body_text_named_params;
  if (Array.isArray(namedSamples) && namedSamples.length) {
    namedSamples.forEach(({ param_name: paramName, example }) => {
      if (paramName) bodySamples.value[paramName] = example ?? '';
    });
  } else {
    const bodyExample = body?.example?.body_text?.[0] || [];
    const detected = detectVariables(body?.text || '');
    detected.forEach((v, idx) => {
      if (bodyExample[idx] !== undefined) {
        bodySamples.value[v] = bodyExample[idx];
      }
    });
  }

  footerEnabled.value = !!footer;
  footerText.value = footer?.text || '';

  buttons.value = (buttonsComp?.buttons || []).map(b => ({
    type: (b.type || '').toUpperCase(),
    text: b.text || '',
    url: b.url || '',
    phone_number: b.phone_number || '',
  }));
};

watch(() => props.initialTemplate, hydrateFromTemplate, { immediate: true });
watch(
  () => props.initialInboxId,
  value => {
    if (value != null) selectedInboxId.value = value;
  },
  { immediate: true }
);

// In create mode, when the inboxes list arrives and nothing is selected
// yet, pick the first Cloud inbox so the operator has a working default.
watch(
  () => props.inboxes,
  next => {
    if (isEdit.value) return;
    if (!selectedInboxId.value && next.length > 0) {
      selectedInboxId.value = next[0].id;
    }
  },
  { immediate: true }
);

const bodyExtracted = computed(() => extractVariables(bodyText.value));
const headerExtracted = computed(() => extractVariables(headerText.value));
const bodyVariables = computed(() => bodyExtracted.value.vars);
const headerVariables = computed(() => headerExtracted.value.vars);
const headerHasVariable = computed(() => headerVariables.value.length > 0);

// Meta rejects a template that mixes {{1}} and {{name}}, and it also
// rejects one where header and body use different styles. Compute the
// single template-wide format (NAMED / POSITIONAL / NONE) and expose a
// list of validation problems the UI surfaces inline. Any non-empty
// problem list disables submit.
const templateFormatIssues = computed(() => {
  const issues = [];
  if (bodyExtracted.value.format === 'MIXED') issues.push('BODY_MIXED');
  if (headerEnabled.value && headerFormat.value === 'TEXT') {
    if (headerExtracted.value.format === 'MIXED') issues.push('HEADER_MIXED');
    const bodyFmt = bodyExtracted.value.format;
    const headerFmt = headerExtracted.value.format;
    const bothHaveVars = bodyFmt !== 'NONE' && headerFmt !== 'NONE';
    if (bothHaveVars && bodyFmt !== headerFmt) {
      issues.push('HEADER_BODY_MISMATCH');
    }
  }
  return issues;
});

const templateParameterFormat = computed(() => {
  if (bodyExtracted.value.format === 'NAMED') return 'NAMED';
  if (headerEnabled.value && headerExtracted.value.format === 'NAMED') {
    return 'NAMED';
  }
  return 'POSITIONAL';
});

const countByType = type => buttons.value.filter(b => b.type === type).length;
const quickReplyCount = computed(() => countByType('QUICK_REPLY'));
const urlCount = computed(() => countByType('URL'));
const phoneCount = computed(() => countByType('PHONE_NUMBER'));

const canAddQuickReply = computed(
  () => quickReplyCount.value < QUICK_REPLY_MAX
);
const canAddUrl = computed(() => urlCount.value < URL_BUTTONS_MAX);
const canAddPhone = computed(() => phoneCount.value < PHONE_BUTTONS_MAX);

const addButton = type => {
  const seed = { type, text: '' };
  if (type === 'URL') seed.url = '';
  if (type === 'PHONE_NUMBER') seed.phone_number = '';
  buttons.value.push(seed);
};

const removeButton = idx => buttons.value.splice(idx, 1);

// Object URL for the preview must be revoked or it leaks memory across
// re-selections. Keep the previous URL around and revoke when we replace
// or clear it.
const clearHeaderMedia = () => {
  if (headerMediaPreviewUrl.value) {
    URL.revokeObjectURL(headerMediaPreviewUrl.value);
  }
  headerMediaHandle.value = null;
  headerMediaPreviewUrl.value = null;
  headerMediaFileName.value = '';
  if (headerFileInput.value) headerFileInput.value.value = '';
};

const onHeaderFormatChange = value => {
  headerFormat.value = value;
  if (value === 'TEXT') clearHeaderMedia();
};

const onHeaderFileSelected = async event => {
  const [file] = event.target.files || [];
  if (!file) return;

  if (file.size > HEADER_MEDIA_MAX_BYTES) {
    useAlert(t('META_TEMPLATES.NEW.FIELDS.HEADER_IMAGE_TOO_LARGE'));
    if (headerFileInput.value) headerFileInput.value.value = '';
    return;
  }

  clearHeaderMedia();
  headerMediaFileName.value = file.name;
  headerMediaPreviewUrl.value = URL.createObjectURL(file);
  headerMediaUploading.value = true;
  try {
    const { data } = await MetaTemplatesAPI.uploadHeaderMedia({
      inboxId: selectedInboxId.value,
      file,
    });
    headerMediaHandle.value = data.handle;
  } catch (err) {
    const message =
      err?.response?.data?.error ||
      t('META_TEMPLATES.NEW.FIELDS.HEADER_IMAGE_UPLOAD_FAILED');
    useAlert(message);
    clearHeaderMedia();
  } finally {
    headerMediaUploading.value = false;
  }
};

const isValid = computed(() => {
  if (!selectedInboxId.value) return false;
  if (!/^[a-z0-9_]{1,512}$/.test(name.value)) return false;

  if (templateFormatIssues.value.length > 0) return false;

  if (!bodyText.value.trim()) return false;
  if (bodyText.value.length > BODY_MAX) return false;
  if (!bodyVariables.value.every(v => (bodySamples.value[v] || '').trim())) {
    return false;
  }

  if (headerEnabled.value) {
    if (headerFormat.value === 'IMAGE') {
      // Meta refuses an IMAGE header without example.header_handle, and
      // an upload in-flight isn't a valid submission state.
      if (!headerMediaHandle.value) return false;
      if (headerMediaUploading.value) return false;
    } else {
      if (!headerText.value.trim()) return false;
      if (headerText.value.length > HEADER_MAX) return false;
      if (headerHasVariable.value && !headerSample.value.trim()) return false;
    }
  }

  if (footerEnabled.value) {
    if (!footerText.value.trim()) return false;
    if (footerText.value.length > FOOTER_MAX) return false;
  }

  const buttonsValid = buttons.value.every(button => {
    if (!button.text?.trim()) return false;
    if (button.text.length > BUTTON_TEXT_MAX) return false;
    if (button.type === 'URL' && !button.url?.trim()) return false;
    if (button.type === 'PHONE_NUMBER' && !button.phone_number?.trim()) {
      return false;
    }
    return true;
  });
  if (!buttonsValid) return false;

  return true;
});

const previewHeader = computed(() => {
  if (!headerEnabled.value) return null;
  if (headerFormat.value === 'IMAGE') {
    return headerMediaPreviewUrl.value
      ? { format: 'IMAGE', mediaPreviewUrl: headerMediaPreviewUrl.value }
      : null;
  }
  return headerText.value ? { format: 'TEXT', text: headerText.value } : null;
});
const previewFooter = computed(() =>
  footerEnabled.value ? footerText.value : ''
);
const previewBodySamples = computed(() => {
  const combined = { ...bodySamples.value };
  if (headerEnabled.value && headerHasVariable.value) {
    const headerVar = headerVariables.value[0];
    if (headerVar != null && combined[headerVar] == null) {
      combined[headerVar] = headerSample.value;
    }
  }
  return combined;
});

const buildPayload = () => {
  const components = [];
  const useNamed = templateParameterFormat.value === 'NAMED';

  if (headerEnabled.value) {
    if (headerFormat.value === 'IMAGE' && headerMediaHandle.value) {
      components.push({
        type: 'HEADER',
        format: 'IMAGE',
        example: { header_handle: [headerMediaHandle.value] },
      });
    } else if (headerFormat.value === 'TEXT' && headerText.value.trim()) {
      const headerComp = {
        type: 'HEADER',
        format: 'TEXT',
        text: headerText.value,
      };
      if (headerHasVariable.value) {
        const headerVar = headerVariables.value[0];
        headerComp.example = useNamed
          ? {
              header_text_named_params: [
                { param_name: headerVar, example: headerSample.value },
              ],
            }
          : { header_text: [headerSample.value] };
      }
      components.push(headerComp);
    }
  }

  const bodyComp = { type: 'BODY', text: bodyText.value };
  if (bodyVariables.value.length > 0) {
    bodyComp.example = useNamed
      ? {
          body_text_named_params: bodyVariables.value.map(v => ({
            param_name: v,
            example: bodySamples.value[v],
          })),
        }
      : { body_text: [bodyVariables.value.map(v => bodySamples.value[v])] };
  }
  components.push(bodyComp);

  if (footerEnabled.value && footerText.value.trim()) {
    components.push({ type: 'FOOTER', text: footerText.value });
  }

  if (buttons.value.length > 0) {
    components.push({
      type: 'BUTTONS',
      buttons: buttons.value.map(b => {
        const out = { type: b.type, text: b.text };
        if (b.type === 'URL') out.url = b.url;
        if (b.type === 'PHONE_NUMBER') out.phone_number = b.phone_number;
        return out;
      }),
    });
  }

  const template = {
    name: name.value,
    language: language.value,
    category: category.value,
    components,
  };
  // parameter_format is only meaningful when the template actually has
  // NAMED placeholders; sending it as POSITIONAL when there are no vars
  // is noisy and Meta already treats absence as positional by default.
  if (useNamed) template.parameter_format = 'NAMED';

  return {
    inboxId: selectedInboxId.value,
    template,
  };
};

const submit = () => {
  if (!isValid.value || props.submitting) return;
  emit('submit', buildPayload());
};

const cancel = () => emit('cancel');
</script>

<template>
  <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_360px] gap-6">
    <form class="grid gap-6" @submit.prevent="submit">
      <!-- Row 1: inbox + name (both locked in edit mode — Meta immutability) -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('META_TEMPLATES.NEW.FIELDS.INBOX') }}
          <select
            v-model="selectedInboxId"
            :disabled="isEdit"
            class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand disabled:opacity-70 disabled:cursor-not-allowed"
          >
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('META_TEMPLATES.NEW.FIELDS.NAME') }}
          <input
            v-model="name"
            type="text"
            maxlength="512"
            :disabled="isEdit"
            class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10 disabled:opacity-70 disabled:cursor-not-allowed"
            :placeholder="t('META_TEMPLATES.NEW.FIELDS.NAME_PLACEHOLDER')"
          />
          <span class="text-xxs text-n-slate-10">
            {{
              isEdit
                ? t('META_TEMPLATES.NEW.FIELDS.NAME_IMMUTABLE')
                : t('META_TEMPLATES.NEW.FIELDS.NAME_HINT')
            }}
          </span>
        </label>
      </div>

      <!-- Row 2: language (locked in edit) + category (editable) -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('META_TEMPLATES.NEW.FIELDS.LANGUAGE') }}
          <select
            v-model="language"
            :disabled="isEdit"
            class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand disabled:opacity-70 disabled:cursor-not-allowed"
          >
            <option v-for="opt in LANGUAGE_OPTIONS" :key="opt" :value="opt">
              {{ opt }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('META_TEMPLATES.NEW.FIELDS.CATEGORY') }}
          <select
            v-model="category"
            class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
          >
            <option v-for="opt in CATEGORY_OPTIONS" :key="opt" :value="opt">
              {{ t(`META_TEMPLATES.CATEGORY.${opt}`, opt) }}
            </option>
          </select>
        </label>
      </div>

      <div
        class="bg-n-alpha-1 border border-n-weak rounded-lg px-3 py-2 text-xs text-n-slate-11 leading-relaxed"
      >
        {{ t(`META_TEMPLATES.NEW.FIELDS.CATEGORY_HINT.${category}`) }}
      </div>

      <!-- Header (optional) -->
      <section class="border border-n-weak rounded-lg p-4 grid gap-3">
        <label
          class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
        >
          <input v-model="headerEnabled" type="checkbox" class="w-4 h-4" />
          {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_TOGGLE') }}
          <span class="text-xs text-n-slate-10">
            {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_TOGGLE_HINT') }}
          </span>
        </label>
        <template v-if="headerEnabled">
          <!-- Format switcher only in create — see hydrateFromTemplate:
               editing a MEDIA header via this form would require a
               re-upload each time, so we stick to TEXT on edit. -->
          <div v-if="!isEdit" class="flex items-center gap-3 text-sm">
            <label
              class="flex items-center gap-1.5 text-n-slate-12 cursor-pointer"
            >
              <input
                type="radio"
                :checked="headerFormat === 'TEXT'"
                @change="onHeaderFormatChange('TEXT')"
              />
              {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_FORMAT_TEXT') }}
            </label>
            <label
              class="flex items-center gap-1.5 text-n-slate-12 cursor-pointer"
            >
              <input
                type="radio"
                :checked="headerFormat === 'IMAGE'"
                @change="onHeaderFormatChange('IMAGE')"
              />
              {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_FORMAT_IMAGE') }}
            </label>
          </div>

          <template v-if="headerFormat === 'TEXT'">
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_TEXT') }}
              <input
                v-model="headerText"
                type="text"
                :maxlength="HEADER_MAX"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10"
                :placeholder="
                  t('META_TEMPLATES.NEW.FIELDS.HEADER_TEXT_PLACEHOLDER')
                "
              />
              <span class="text-xxs text-n-slate-10">
                {{
                  t('META_TEMPLATES.NEW.FIELDS.HEADER_HINT_WITH_COUNT', {
                    count: headerText.length,
                    max: HEADER_MAX,
                  })
                }}
              </span>
            </label>
            <label
              v-if="headerHasVariable"
              class="flex flex-col gap-1 text-xs text-n-slate-11"
            >
              {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_SAMPLE') }}
              <input
                v-model="headerSample"
                type="text"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
              />
            </label>
          </template>

          <div v-else class="flex flex-col gap-2 text-xs text-n-slate-11">
            <span>{{ t('META_TEMPLATES.NEW.FIELDS.HEADER_IMAGE_LABEL') }}</span>
            <div class="flex items-center gap-3">
              <input
                ref="headerFileInput"
                type="file"
                :accept="HEADER_MEDIA_ACCEPTED_TYPES"
                class="text-xs text-n-slate-12 file:mr-3 file:px-3 file:h-9 file:rounded-md file:border-0 file:bg-n-brand file:text-white file:cursor-pointer file:text-xs"
                @change="onHeaderFileSelected"
              />
              <Spinner v-if="headerMediaUploading" class="!w-4 !h-4 !p-0" />
              <span
                v-else-if="headerMediaHandle"
                class="text-xxs text-n-teal-11"
              >
                {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_IMAGE_READY') }}
              </span>
            </div>
            <span
              v-if="headerMediaFileName"
              class="text-xxs text-n-slate-10 truncate"
            >
              {{ headerMediaFileName }}
            </span>
            <span class="text-xxs text-n-slate-10">
              {{ t('META_TEMPLATES.NEW.FIELDS.HEADER_IMAGE_HINT') }}
            </span>
          </div>
        </template>
      </section>

      <!-- Body -->
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('META_TEMPLATES.NEW.FIELDS.BODY') }}
        <textarea
          v-model="bodyText"
          rows="6"
          :maxlength="BODY_MAX"
          class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 py-2 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10 resize-y"
          :placeholder="t('META_TEMPLATES.NEW.FIELDS.BODY_PLACEHOLDER')"
        />
        <span class="text-xxs text-n-slate-10">
          {{
            t('META_TEMPLATES.NEW.FIELDS.BODY_HINT_WITH_COUNT', {
              count: bodyText.length,
              max: BODY_MAX,
            })
          }}
        </span>
      </label>

      <div
        v-if="templateFormatIssues.length > 0"
        class="border border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11 rounded-lg px-3 py-2 text-xs leading-relaxed grid gap-1"
      >
        <p v-for="issue in templateFormatIssues" :key="issue">
          {{ t(`META_TEMPLATES.NEW.FIELDS.VAR_ISSUES.${issue}`) }}
        </p>
      </div>

      <!-- Body sample values -->
      <fieldset
        v-if="bodyVariables.length > 0"
        class="border border-n-weak rounded-lg p-4 grid gap-3"
      >
        <legend class="px-2 text-xs text-n-slate-11">
          {{ t('META_TEMPLATES.NEW.FIELDS.SAMPLES_TITLE') }}
        </legend>
        <p class="text-xs text-n-slate-10">
          {{ t('META_TEMPLATES.NEW.FIELDS.SAMPLES_DESCRIPTION') }}
        </p>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <label
            v-for="v in bodyVariables"
            :key="v"
            class="flex flex-col gap-1 text-xs text-n-slate-11"
          >
            {{ t('META_TEMPLATES.NEW.FIELDS.SAMPLE_FOR', { index: v }) }}
            <input
              v-model="bodySamples[v]"
              type="text"
              class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
            />
          </label>
        </div>
      </fieldset>

      <!-- Footer (optional) -->
      <section class="border border-n-weak rounded-lg p-4 grid gap-3">
        <label
          class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
        >
          <input v-model="footerEnabled" type="checkbox" class="w-4 h-4" />
          {{ t('META_TEMPLATES.NEW.FIELDS.FOOTER_TOGGLE') }}
          <span class="text-xs text-n-slate-10">
            {{ t('META_TEMPLATES.NEW.FIELDS.FOOTER_TOGGLE_HINT') }}
          </span>
        </label>
        <label
          v-if="footerEnabled"
          class="flex flex-col gap-1 text-xs text-n-slate-11"
        >
          <input
            v-model="footerText"
            type="text"
            :maxlength="FOOTER_MAX"
            class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10"
            :placeholder="t('META_TEMPLATES.NEW.FIELDS.FOOTER_PLACEHOLDER')"
          />
          <span class="text-xxs text-n-slate-10">
            {{
              t('META_TEMPLATES.NEW.FIELDS.FOOTER_HINT_WITH_COUNT', {
                count: footerText.length,
                max: FOOTER_MAX,
              })
            }}
          </span>
        </label>
      </section>

      <!-- Buttons -->
      <section class="border border-n-weak rounded-lg p-4 grid gap-3">
        <div class="flex items-baseline justify-between gap-2 flex-wrap">
          <div class="text-sm text-n-slate-12 font-medium">
            {{ t('META_TEMPLATES.NEW.FIELDS.BUTTONS_TITLE') }}
            <span class="text-xs text-n-slate-10 font-normal ml-1">
              {{ t('META_TEMPLATES.NEW.FIELDS.BUTTONS_HINT') }}
            </span>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              sm
              faded
              slate
              type="button"
              :disabled="!canAddQuickReply"
              :label="
                t('META_TEMPLATES.NEW.FIELDS.ADD_QUICK_REPLY', {
                  count: quickReplyCount,
                  max: QUICK_REPLY_MAX,
                })
              "
              @click="addButton('QUICK_REPLY')"
            />
            <Button
              sm
              faded
              slate
              type="button"
              :disabled="!canAddUrl"
              :label="
                t('META_TEMPLATES.NEW.FIELDS.ADD_URL', {
                  count: urlCount,
                  max: URL_BUTTONS_MAX,
                })
              "
              @click="addButton('URL')"
            />
            <Button
              sm
              faded
              slate
              type="button"
              :disabled="!canAddPhone"
              :label="
                t('META_TEMPLATES.NEW.FIELDS.ADD_PHONE', {
                  count: phoneCount,
                  max: PHONE_BUTTONS_MAX,
                })
              "
              @click="addButton('PHONE_NUMBER')"
            />
          </div>
        </div>
        <ul v-if="buttons.length > 0" class="grid gap-3">
          <li
            v-for="(button, idx) in buttons"
            :key="idx"
            class="grid gap-2 border border-n-weak rounded-lg p-3"
          >
            <div class="flex items-center justify-between">
              <span class="text-xxs uppercase tracking-wide text-n-slate-11">
                {{ t(`META_TEMPLATES.NEW.FIELDS.BUTTON_TYPE.${button.type}`) }}
              </span>
              <button
                type="button"
                class="text-xxs text-n-ruby-11 hover:underline"
                @click="removeButton(idx)"
              >
                {{ t('META_TEMPLATES.NEW.FIELDS.REMOVE_BUTTON') }}
              </button>
            </div>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.NEW.FIELDS.BUTTON_TEXT') }}
              <input
                v-model="button.text"
                type="text"
                :maxlength="BUTTON_TEXT_MAX"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
              />
            </label>
            <label
              v-if="button.type === 'URL'"
              class="flex flex-col gap-1 text-xs text-n-slate-11"
            >
              {{ t('META_TEMPLATES.NEW.FIELDS.BUTTON_URL') }}
              <input
                v-model="button.url"
                type="url"
                :placeholder="
                  t('META_TEMPLATES.NEW.FIELDS.BUTTON_URL_PLACEHOLDER')
                "
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10"
              />
            </label>
            <label
              v-if="button.type === 'PHONE_NUMBER'"
              class="flex flex-col gap-1 text-xs text-n-slate-11"
            >
              {{ t('META_TEMPLATES.NEW.FIELDS.BUTTON_PHONE') }}
              <input
                v-model="button.phone_number"
                type="tel"
                :placeholder="
                  t('META_TEMPLATES.NEW.FIELDS.BUTTON_PHONE_PLACEHOLDER')
                "
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10"
              />
            </label>
          </li>
        </ul>
      </section>

      <div class="flex justify-end gap-2">
        <Button faded slate type="button" @click="cancel">
          {{ t('META_TEMPLATES.NEW.CANCEL') }}
        </Button>
        <Button solid blue type="submit" :disabled="!isValid || submitting">
          <Spinner v-if="submitting" class="!w-4 !h-4 !p-0" />
          <span v-else>
            {{
              isEdit
                ? t('META_TEMPLATES.EDIT.SUBMIT')
                : t('META_TEMPLATES.NEW.SUBMIT')
            }}
          </span>
        </Button>
      </div>
    </form>

    <aside class="lg:sticky lg:top-4 h-fit">
      <TemplatePreview
        :header="previewHeader"
        :body="bodyText"
        :body-samples="previewBodySamples"
        :footer="previewFooter"
        :buttons="buttons"
      />
    </aside>
  </div>
</template>
