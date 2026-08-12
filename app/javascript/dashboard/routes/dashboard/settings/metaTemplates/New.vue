<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplateForm from './components/TemplateForm.vue';

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { stashWriteSeed } from './writeSeed';
import { ref } from 'vue';

const { t } = useI18n();
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
      <TemplateForm
        mode="create"
        :inboxes="cloudInboxes"
        :submitting="submitting"
        @submit="handleSubmit"
        @cancel="handleCancel"
      />
    </template>
  </SettingsLayout>
</template>
