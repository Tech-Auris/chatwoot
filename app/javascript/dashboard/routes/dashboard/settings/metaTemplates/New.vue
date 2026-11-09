<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplateForm from './components/TemplateForm.vue';

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { stashWriteSeed } from './writeSeed';
import { SYSTEM_LOCKED_FIELDS } from './kit';
import { ref } from 'vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

// Thin wrapper around TemplateForm. Owns the create-side glue: which
// inboxes are available, calling the create endpoint on submit, and
// routing back to the list. The form component holds every field, its
// validation, and the live preview panel.

const inboxes = useMapGetter('inboxes/getInboxes');
const cloudInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const submitting = ref(false);

// "Usar modelo" on the Kit Auris tab lands here with ?kit=<name>&inbox_id=,
// and the form opens filled from the kit. System templates keep everything
// but the body locked and only take the engine variables.
const kitName = route.query.kit;
const kitInboxId = route.query.inbox_id ? Number(route.query.inbox_id) : null;
const kitTemplate = ref(null);
const systemVariables = ref(null);
const isSystemTemplate = computed(() => kitTemplate.value?.group === 'system');

const loadKitTemplate = async () => {
  try {
    const { data } = await MetaTemplatesAPI.kit({ inboxId: kitInboxId });
    kitTemplate.value = data.templates.find(item => item.name === kitName);
    systemVariables.value = data.system_variables;
  } catch (err) {
    useAlert(err?.response?.data?.error || t('META_TEMPLATES.KIT.LOAD_FAILED'));
  }
  if (!kitTemplate.value) router.push({ name: 'meta_templates_index' });
};

const handleSubmit = async ({ inboxId, template }) => {
  submitting.value = true;
  try {
    const { data } = await MetaTemplatesAPI.create({ inboxId, template });
    // Hand Index the fresh list we just got back from the server so it
    // renders the new template on the very first paint after redirect.
    // Without this, Index re-fetches on mount and — because Meta's list
    // endpoint is eventually consistent — sometimes shows the pre-create
    // list, leaving the operator to hit Sincronizar to see their own
    // submission.
    stashWriteSeed({
      inboxId,
      templates: data.templates,
      lastSyncedAt: data.last_synced_at,
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

const handleCancel = () => router.push({ name: 'meta_templates_index' });

onMounted(() => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  if (kitName && kitInboxId) loadKitTemplate();
});
</script>

<template>
  <SettingsLayout
    :is-loading="!!kitName && !kitTemplate"
    :loading-message="t('META_TEMPLATES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('META_TEMPLATES.NEW.TITLE')"
        :description="t('META_TEMPLATES.NEW.DESCRIPTION')"
      />
    </template>

    <template #body>
      <TemplateForm
        mode="create"
        :inboxes="cloudInboxes"
        :initial-template="kitTemplate"
        :initial-inbox-id="kitTemplate ? kitInboxId : null"
        :locked-fields="isSystemTemplate ? SYSTEM_LOCKED_FIELDS : []"
        :allowed-variables="isSystemTemplate ? systemVariables : null"
        :submitting="submitting"
        @submit="handleSubmit"
        @cancel="handleCancel"
      />
    </template>
  </SettingsLayout>
</template>
