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

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

// Fatia 3a scope: metadata + body-only template. Header, footer and
// buttons come in Fatia 3b, alongside the live preview and rich media.

const inboxes = useMapGetter('inboxes/getInboxes');
const cloudInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

// Same option set the read-only list uses, so the operator sees the
// exact filter values on the way back after saving.
const CATEGORY_OPTIONS = ['MARKETING', 'UTILITY', 'AUTHENTICATION'];
// Language picker mirrors what Meta currently accepts on the Cloud
// API — kept short here so operators pick from the same list they see
// on business.facebook.com; expand as clients need more locales.
const LANGUAGE_OPTIONS = ['pt_BR', 'en', 'en_US', 'es', 'es_ES'];

const selectedInboxId = ref(null);
const name = ref('');
const language = ref('pt_BR');
const category = ref('UTILITY');
const bodyText = ref('');
const submitting = ref(false);

// Meta requires sample values for every `{{n}}` placeholder in the body.
// Reactive scan on every keystroke so the sample-values grid mirrors
// what the operator is typing.
const bodyVariables = computed(() => {
  const matches = bodyText.value.match(/\{\{(\d+)\}\}/g) || [];
  const uniqueOrdered = [...new Set(matches)].sort(
    (a, b) => Number(a.replace(/[{}]/g, '')) - Number(b.replace(/[{}]/g, ''))
  );
  return uniqueOrdered.map(m => m.replace(/[{}]/g, ''));
});

// Local map from variable index (as string) → sample value. Entries stay
// around when a variable is temporarily removed from the body so the
// operator does not lose typing while editing.
const sampleValues = ref({});

const isValid = computed(() => {
  if (!selectedInboxId.value) return false;
  if (!/^[a-z0-9_]{1,512}$/.test(name.value)) return false;
  if (!bodyText.value.trim()) return false;
  if (bodyText.value.length > 1024) return false;
  return bodyVariables.value.every(v => (sampleValues.value[v] || '').trim());
});

const buildPayload = () => {
  const bodyComponent = { type: 'BODY', text: bodyText.value };
  if (bodyVariables.value.length > 0) {
    bodyComponent.example = {
      body_text: [bodyVariables.value.map(v => sampleValues.value[v])],
    };
  }
  return {
    name: name.value,
    language: language.value,
    category: category.value,
    components: [bodyComponent],
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
      <form class="grid gap-6 max-w-3xl" @submit.prevent="submit">
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

        <!-- Body -->
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('META_TEMPLATES.NEW.FIELDS.BODY') }}
          <textarea
            v-model="bodyText"
            rows="6"
            maxlength="1024"
            class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 py-2 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10 resize-y"
            :placeholder="t('META_TEMPLATES.NEW.FIELDS.BODY_PLACEHOLDER')"
          />
          <span class="text-xxs text-n-slate-10">
            {{
              t('META_TEMPLATES.NEW.FIELDS.BODY_HINT_WITH_COUNT', {
                count: bodyText.length,
                max: 1024,
              })
            }}
          </span>
        </label>

        <!-- Sample values for each detected variable -->
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
                v-model="sampleValues[v]"
                type="text"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand"
              />
            </label>
          </div>
        </fieldset>

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
    </template>
  </SettingsLayout>
</template>
