<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Switch from 'dashboard/components-next/switch/Switch.vue';

// "IA responde este contato": on by default; turned off, every new message of
// the contact, in any inbox or conversation, arrives with the AI off. Shows
// when it was turned off and by whom.
const props = defineProps({
  contactId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();
const contactGetter = useMapGetter('contacts/getContact');

const contact = computed(() => contactGetter.value(props.contactId) || {});
const isAiOn = computed(() => !contact.value.ai_disabled);
const isSaving = ref(false);

const offSince = computed(() => {
  if (isAiOn.value || !contact.value.ai_disabled_at) return '';
  return t('CONTACT_PANEL.AI_DISABLED.OFF_SINCE', {
    date: format(
      new Date(contact.value.ai_disabled_at * 1000),
      'dd/MM/yyyy HH:mm'
    ),
    user: contact.value.ai_disabled_by_name || '-',
  });
});

const toggle = async enabled => {
  isSaving.value = true;
  try {
    await store.dispatch('contacts/setAiStatus', {
      id: props.contactId,
      enabled,
    });
    useAlert(
      enabled
        ? t('CONTACT_PANEL.AI_DISABLED.TURNED_ON')
        : t('CONTACT_PANEL.AI_DISABLED.TURNED_OFF')
    );
  } catch {
    useAlert(t('CONTACT_PANEL.AI_DISABLED.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full gap-1 px-3 py-2.5 border rounded-lg"
    :class="isAiOn ? 'border-n-weak' : 'border-n-amber-6 bg-n-amber-2'"
  >
    <div class="flex items-center justify-between gap-2">
      <label
        :for="`ai-status-${contactId}`"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t('CONTACT_PANEL.AI_DISABLED.TITLE') }}
      </label>
      <Switch
        :id="`ai-status-${contactId}`"
        :model-value="isAiOn"
        :disabled="isSaving"
        @update:model-value="toggle"
      />
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('CONTACT_PANEL.AI_DISABLED.HELP') }}
    </p>
    <p v-if="offSince" class="mb-0 text-xs text-n-amber-11">
      {{ offSince }}
    </p>
  </div>
</template>
