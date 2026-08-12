<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplateForm from './components/TemplateForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { stashWriteSeed } from './writeSeed';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

// Edit wrapper. Reuses TemplateForm in `edit` mode. URL carries the
// template id in the path and the inbox id in the query — we resolve
// the template from the cached list on that inbox and pass it into
// the form as `initialTemplate`. Locking of name / language / inbox
// happens inside TemplateForm.

const inboxes = useMapGetter('inboxes/getInboxes');
const cloudInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const templateId = computed(() => route.params.id);
const inboxIdFromQuery = computed(() =>
  route.query.inbox_id ? Number(route.query.inbox_id) : null
);

const template = ref(null);
// Start in loading so the very first paint shows the spinner instead of
// an empty body. Without this the operator briefly sees blank content
// before the async fetchTemplate ticks loading to true.
const loading = ref(true);
const submitting = ref(false);

const findTemplateIn = list =>
  (list || []).find(t2 => String(t2.id) === String(templateId.value));

const fetchTemplate = async () => {
  if (!inboxIdFromQuery.value || !templateId.value) return;
  loading.value = true;
  try {
    const { data } = await MetaTemplatesAPI.fetch({
      inboxId: inboxIdFromQuery.value,
    });
    template.value = findTemplateIn(data.templates);

    // Deep-links, refreshes and inboxes whose initial `after_create :
    // sync_templates` never landed can leave the local cache empty or
    // stale enough to miss the id in the URL. Instead of bouncing the
    // operator back to the index, force a fresh Meta sync once and
    // retry — matches the auto-sync behavior on the index page but
    // scoped to the specific id we came here for.
    if (!template.value) {
      const { data: synced } = await MetaTemplatesAPI.sync({
        inboxId: inboxIdFromQuery.value,
      });
      template.value = findTemplateIn(synced.templates);
    }

    if (!template.value) {
      useAlert(t('META_TEMPLATES.EDIT.NOT_FOUND'));
      router.push({ name: 'meta_templates_index' });
    }
  } catch (err) {
    useAlert(
      err?.response?.data?.error || t('META_TEMPLATES.ERRORS.FETCH_FAILED')
    );
  } finally {
    loading.value = false;
  }
};

const handleSubmit = async ({ template: payload }) => {
  submitting.value = true;
  try {
    const { data } = await MetaTemplatesAPI.update({
      inboxId: inboxIdFromQuery.value,
      templateId: templateId.value,
      template: payload,
    });
    // Same bridge trick as New.vue — hand Index the fresh list from the
    // update response so it renders the just-flipped-to-PENDING template
    // on the very first paint after redirect, without depending on the
    // next GET seeing the write (see writeSeed.js).
    stashWriteSeed({
      inboxId: inboxIdFromQuery.value,
      templates: data.templates,
      lastSyncedAt: data.last_synced_at,
    });
    useAlert(t('META_TEMPLATES.EDIT.SUCCESS'));
    router.push({ name: 'meta_templates_index' });
  } catch (err) {
    const data = err?.response?.data || {};
    const details = data.details ? ` (${data.details})` : '';
    useAlert((data.error || t('META_TEMPLATES.EDIT.ERROR_GENERIC')) + details);
  } finally {
    submitting.value = false;
  }
};

const handleCancel = () => router.push({ name: 'meta_templates_index' });

// Meta only allows edits on APPROVED templates. When the operator deep-
// links (or refreshes) an Edit URL for a template in another status,
// we render an explanatory panel instead of the form — otherwise they
// would fill it in and only find out Meta rejected the edit at submit.
const isEditable = computed(
  () => (template.value?.status || '').toUpperCase() === 'APPROVED'
);

const notEditableReason = computed(() => {
  if (!template.value) return '';
  return t('META_TEMPLATES.EDIT.NOT_EDITABLE', {
    status: (template.value.status || 'UNKNOWN').toUpperCase(),
  });
});

watch([templateId, inboxIdFromQuery], () => fetchTemplate(), {
  immediate: true,
});

onMounted(() => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="loading && !template"
    :loading-message="t('META_TEMPLATES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('META_TEMPLATES.EDIT.TITLE')"
        :description="t('META_TEMPLATES.EDIT.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div
        v-if="template && !isEditable"
        class="rounded-lg border border-n-weak p-6 flex flex-col items-start gap-3 bg-n-alpha-1"
      >
        <p class="text-sm text-n-slate-12">{{ notEditableReason }}</p>
        <Button
          faded
          slate
          sm
          :label="t('META_TEMPLATES.EDIT.BACK_TO_LIST')"
          @click="handleCancel"
        />
      </div>
      <TemplateForm
        v-else-if="template"
        mode="edit"
        :inboxes="cloudInboxes"
        :initial-template="template"
        :initial-inbox-id="inboxIdFromQuery"
        :submitting="submitting"
        @submit="handleSubmit"
        @cancel="handleCancel"
      />
    </template>
  </SettingsLayout>
</template>
