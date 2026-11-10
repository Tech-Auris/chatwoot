<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import StatusBadge from './StatusBadge.vue';
import MetaTemplatesAPI from 'dashboard/api/metaTemplates';
import { KIT_GROUPS, bodyText } from '../kit';

// "Kit Auris" tab: the follow-up templates installed with the number, the
// system templates the Auris engine sends by name and the suggested ones.
// "Usar modelo" opens the create form filled from the kit; a template the
// WABA already has opens its detail instead.
const props = defineProps({
  inboxId: { type: [Number, String], default: null },
  canCreate: { type: Boolean, default: false },
  // Bumped by the parent to refetch (page reactivated, sync done).
  reloadKey: { type: Number, default: 0 },
});

const emit = defineEmits(['openTemplate']);

const { t } = useI18n();
const router = useRouter();

const kit = ref([]);
const loading = ref(false);

const sections = computed(() =>
  KIT_GROUPS.map(group => ({
    group,
    templates: kit.value.filter(template => template.group === group),
  }))
);

const fetchKit = async () => {
  if (!props.inboxId) return;
  loading.value = true;
  try {
    const { data } = await MetaTemplatesAPI.kit({ inboxId: props.inboxId });
    kit.value = data.templates || [];
  } catch (err) {
    useAlert(err?.response?.data?.error || t('META_TEMPLATES.KIT.LOAD_FAILED'));
    kit.value = [];
  } finally {
    loading.value = false;
  }
};

watch(() => [props.inboxId, props.reloadKey], fetchKit, { immediate: true });

const useTemplate = template => {
  router.push({
    name: 'meta_templates_new',
    query: { kit: template.name, inbox_id: props.inboxId },
  });
};
</script>

<template>
  <div v-if="loading && !kit.length" class="flex justify-center py-12">
    <Spinner />
  </div>
  <div v-else class="grid gap-8">
    <section
      v-for="section in sections"
      :key="section.group"
      class="grid gap-3"
    >
      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t(`META_TEMPLATES.KIT.GROUPS.${section.group}.TITLE`) }}
        </h3>
        <p class="text-xs text-n-slate-11">
          {{ t(`META_TEMPLATES.KIT.GROUPS.${section.group}.DESCRIPTION`) }}
        </p>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        <article
          v-for="template in section.templates"
          :key="template.name"
          class="flex flex-col gap-3 border border-n-weak rounded-lg p-4 bg-n-alpha-1"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ template.name }}
              </p>
              <p class="text-xxs text-n-slate-10">
                {{ t(`META_TEMPLATES.CATEGORY.${template.category}`) }}
              </p>
            </div>
            <StatusBadge
              v-if="template.existing_status"
              :status="template.existing_status"
            />
            <span
              v-else-if="section.group === 'follow_up'"
              class="text-xxs text-n-slate-11 shrink-0"
            >
              {{ t('META_TEMPLATES.KIT.NOT_INSTALLED') }}
            </span>
          </div>
          <p
            class="flex-1 text-xs text-n-slate-11 whitespace-pre-line line-clamp-4"
          >
            {{ bodyText(template) }}
          </p>
          <div class="flex items-center justify-between gap-2">
            <span
              v-if="template.existing_status"
              class="text-xxs text-n-slate-10"
            >
              {{ t('META_TEMPLATES.KIT.ALREADY_CREATED') }}
            </span>
            <span v-else />
            <Button
              v-if="template.existing_id"
              sm
              faded
              slate
              :label="t('META_TEMPLATES.KIT.VIEW')"
              @click="emit('openTemplate', template.existing_id)"
            />
            <Button
              v-else-if="canCreate && section.group !== 'follow_up'"
              sm
              faded
              blue
              :label="t('META_TEMPLATES.KIT.USE')"
              @click="useTemplate(template)"
            />
          </div>
        </article>
      </div>
    </section>
  </div>
</template>
