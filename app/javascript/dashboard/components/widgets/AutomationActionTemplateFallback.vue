<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

import NextButton from 'dashboard/components-next/button/Button.vue';
import TemplateQualityBadge from 'dashboard/components-next/whatsapp/TemplateQualityBadge.vue';
import TemplateQualityWarning from 'dashboard/components-next/whatsapp/TemplateQualityWarning.vue';
import { findTemplate } from 'dashboard/helper/templateQuality';
import WhatsappTemplates from 'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue';

// The template an automation falls back to when WhatsApp Cloud refuses the
// text (24h window closed). Templates belong to the inbox's number, so they
// can only be listed when the rule has an inbox condition. Picking one emits
// `(templateParams, renderedText)` so the parent can fill an empty text.
const props = defineProps({
  modelValue: {
    type: Object,
    default: null,
  },
  conditions: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();

const showModal = ref(false);

const hasTemplate = computed(
  () => !!props.modelValue && Object.keys(props.modelValue).length > 0
);

const templateName = computed(
  () => props.modelValue?.name || props.modelValue?.id || null
);

const inboxIdsFromConditions = computed(() =>
  props.conditions
    .filter(condition => condition.attribute_key === 'inbox_id')
    .flatMap(condition => [condition.values].flat())
    .map(value => Number(typeof value === 'object' ? value?.id : value))
    .filter(Boolean)
);

const inboxIdForTemplates = computed(
  () =>
    inboxIdsFromConditions.value.find(
      inboxId =>
        (store.getters['inboxes/getWhatsAppTemplates'](inboxId) || []).length >
        0
    ) ?? null
);

const selectedTemplate = computed(() =>
  findTemplate(
    store.getters['inboxes/getWhatsAppTemplates'](inboxIdForTemplates.value),
    props.modelValue
  )
);

const onTemplateSelect = payload => {
  emit('update:modelValue', payload.templateParams, payload.message);
  showModal.value = false;
};

const clearTemplate = () => emit('update:modelValue', null);
</script>

<template>
  <div class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-1">
    <span class="text-xs font-medium text-n-slate-12">
      {{ t('AUTOMATION.ACTION.TEMPLATE_FALLBACK.TITLE') }}
    </span>
    <span class="text-xs text-n-slate-11">
      {{ t('AUTOMATION.ACTION.TEMPLATE_FALLBACK.HELP') }}
    </span>

    <template v-if="hasTemplate">
      <div class="flex items-center gap-2 text-xs text-n-slate-11">
        <span>
          {{ t('AUTOMATION.ACTION.TEMPLATE_SELECTED', { name: templateName }) }}
        </span>
        <TemplateQualityBadge
          v-if="selectedTemplate"
          :template="selectedTemplate"
        />
        <NextButton ghost xs slate icon="i-lucide-x" @click="clearTemplate" />
      </div>
      <TemplateQualityWarning
        v-if="selectedTemplate"
        :template="selectedTemplate"
      />
    </template>
    <div v-else-if="inboxIdForTemplates">
      <NextButton
        ghost
        xs
        icon="i-lucide-zap"
        :label="t('AUTOMATION.ACTION.TEMPLATE_SELECT')"
        @click="showModal = true"
      />
    </div>
    <span v-else class="text-xs text-n-amber-11">
      {{ t('AUTOMATION.ACTION.TEMPLATE_FALLBACK.NEEDS_INBOX') }}
    </span>

    <WhatsappTemplates
      v-if="inboxIdForTemplates"
      v-model:show="showModal"
      :inbox-id="inboxIdForTemplates"
      :send-button-label="t('AUTOMATION.ACTION.TEMPLATE_USE')"
      @on-send="onTemplateSelect"
      @cancel="showModal = false"
    />
  </div>
</template>
