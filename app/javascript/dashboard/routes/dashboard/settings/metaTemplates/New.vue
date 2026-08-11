<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import TemplatePreview from './components/TemplatePreview.vue';

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

// Fatia 3b: header TEXT + footer + buttons on top of Fatia 3a's body-only
// baseline, plus the live WhatsApp-style preview panel on the right.
// Header media (IMAGE / VIDEO / DOCUMENT) needs Meta's resumable upload
// handle flow and belongs to Fatia 3c.

const inboxes = useMapGetter('inboxes/getInboxes');
const cloudInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const CATEGORY_OPTIONS = ['MARKETING', 'UTILITY', 'AUTHENTICATION'];
const LANGUAGE_OPTIONS = ['pt_BR', 'en', 'en_US', 'es', 'es_ES'];

// Meta limits (per docs, WhatsApp Business Platform v18+):
//   header TEXT: ≤ 60 chars, at most 1 variable
//   body: ≤ 1024 chars, N variables
//   footer: ≤ 60 chars, no variables
//   buttons: mixed set of at most 3 quick_reply OR at most 2 URL + 1 phone
const HEADER_MAX = 60;
const BODY_MAX = 1024;
const FOOTER_MAX = 60;
const QUICK_REPLY_MAX = 3;
const URL_BUTTONS_MAX = 2;
const PHONE_BUTTONS_MAX = 1;
const BUTTON_TEXT_MAX = 25;

const selectedInboxId = ref(null);
const name = ref('');
const language = ref('pt_BR');
const category = ref('UTILITY');

// Header
const headerEnabled = ref(false);
const headerText = ref('');
const headerSample = ref('');

// Body
const bodyText = ref('');
const bodySamples = ref({});

// Footer
const footerEnabled = ref(false);
const footerText = ref('');

// Buttons — a flat list; the UI enforces the type-mix limits so the
// operator never composes something Meta will reject wholesale.
const buttons = ref([]);

const submitting = ref(false);

const detectVariables = text => {
  const matches = text.match(/\{\{(\d+)\}\}/g) || [];
  return [...new Set(matches)]
    .sort(
      (a, b) => Number(a.replace(/[{}]/g, '')) - Number(b.replace(/[{}]/g, ''))
    )
    .map(m => m.replace(/[{}]/g, ''));
};

const bodyVariables = computed(() => detectVariables(bodyText.value));
const headerHasVariable = computed(() =>
  /\{\{1\}\}/.test(headerText.value || '')
);

// Button counters, used both to enforce add-buttons and to render the
// "N/max" labels on the buttons toolbar.
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

const isValid = computed(() => {
  if (!selectedInboxId.value) return false;
  if (!/^[a-z0-9_]{1,512}$/.test(name.value)) return false;

  if (!bodyText.value.trim()) return false;
  if (bodyText.value.length > BODY_MAX) return false;
  if (!bodyVariables.value.every(v => (bodySamples.value[v] || '').trim())) {
    return false;
  }

  if (headerEnabled.value) {
    if (!headerText.value.trim()) return false;
    if (headerText.value.length > HEADER_MAX) return false;
    if (headerHasVariable.value && !headerSample.value.trim()) return false;
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

const previewHeader = computed(() =>
  headerEnabled.value && headerText.value
    ? { format: 'TEXT', text: headerText.value }
    : null
);
const previewFooter = computed(() =>
  footerEnabled.value ? footerText.value : ''
);
const previewBodySamples = computed(() => {
  const combined = { ...bodySamples.value };
  if (headerEnabled.value && headerHasVariable.value) {
    combined['1'] = combined['1'] ?? headerSample.value;
  }
  return combined;
});

const buildPayload = () => {
  const components = [];

  if (headerEnabled.value && headerText.value.trim()) {
    const headerComp = {
      type: 'HEADER',
      format: 'TEXT',
      text: headerText.value,
    };
    if (headerHasVariable.value) {
      headerComp.example = { header_text: [headerSample.value] };
    }
    components.push(headerComp);
  }

  const bodyComp = { type: 'BODY', text: bodyText.value };
  if (bodyVariables.value.length > 0) {
    bodyComp.example = {
      body_text: [bodyVariables.value.map(v => bodySamples.value[v])],
    };
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

  return {
    name: name.value,
    language: language.value,
    category: category.value,
    components,
  };
};

const submit = async () => {
  if (!isValid.value || submitting.value) return;
  submitting.value = true;
  try {
    await MetaTemplatesAPI.create({
      inboxId: selectedInboxId.value,
      template: buildPayload(),
    });
    useAlert(t('META_TEMPLATES.NEW.SUCCESS'));
    router.push({ name: 'meta_templates_index' });
  } catch (err) {
    const data = err?.response?.data || {};
    const details = data.details ? ` (${data.details})` : '';
    useAlert((data.error || t('META_TEMPLATES.NEW.ERROR_GENERIC')) + details);
  } finally {
    submitting.value = false;
  }
};

const cancel = () => router.push({ name: 'meta_templates_index' });

watch(
  cloudInboxes,
  next => {
    if (!selectedInboxId.value && next.length > 0) {
      selectedInboxId.value = next[0].id;
    }
  },
  { immediate: true }
);

onMounted(() => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
});
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="t('META_TEMPLATES.NEW.TITLE')"
        :description="t('META_TEMPLATES.NEW.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_360px] gap-6">
        <form class="grid gap-6" @submit.prevent="submit">
          <!-- Row 1: inbox + name -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.NEW.FIELDS.INBOX') }}
              <select
                v-model="selectedInboxId"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
              >
                <option
                  v-for="inbox in cloudInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
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
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10"
                :placeholder="t('META_TEMPLATES.NEW.FIELDS.NAME_PLACEHOLDER')"
              />
              <span class="text-xxs text-n-slate-10">
                {{ t('META_TEMPLATES.NEW.FIELDS.NAME_HINT') }}
              </span>
            </label>
          </div>

          <!-- Row 2: language + category -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.NEW.FIELDS.LANGUAGE') }}
              <select
                v-model="language"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
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

          <!-- Buttons (optional) -->
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
                  <span
                    class="text-xxs uppercase tracking-wide text-n-slate-11"
                  >
                    {{
                      t(`META_TEMPLATES.NEW.FIELDS.BUTTON_TYPE.${button.type}`)
                    }}
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
              <span v-else>{{ t('META_TEMPLATES.NEW.SUBMIT') }}</span>
            </Button>
          </div>
        </form>

        <!-- Live preview panel (sticks on scroll on wide screens) -->
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
  </SettingsLayout>
</template>
