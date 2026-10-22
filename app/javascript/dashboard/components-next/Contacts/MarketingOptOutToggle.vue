<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Switch from 'dashboard/components-next/switch/Switch.vue';

// The contact's marketing opt-out: with it on, campaigns and follow-ups skip
// the contact, while replies, reminders and confirmations keep going out.
// Shows when it was turned on and by whom (agent, Meta, template button, AI).
const props = defineProps({
  contactId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();
const contactGetter = useMapGetter('contacts/getContact');

const contact = computed(() => contactGetter.value(props.contactId) || {});
const isOptedOut = computed(() => !!contact.value.marketing_opt_out);
const isSaving = ref(false);

const sourceLabel = computed(
  () =>
    ({
      manual: t('CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.MANUAL'),
      meta: t('CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.META'),
      template_button: t(
        'CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.TEMPLATE_BUTTON'
      ),
      ai: t('CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.AI'),
    })[contact.value.marketing_opt_out_source]
);

const description = computed(() => {
  if (!isOptedOut.value) return t('CONTACT_PANEL.MARKETING_OPT_OUT.OFF_HELP');
  if (!contact.value.marketing_opt_out_at) return sourceLabel.value;
  return t('CONTACT_PANEL.MARKETING_OPT_OUT.ON_SINCE', {
    date: format(
      new Date(contact.value.marketing_opt_out_at * 1000),
      'dd/MM/yyyy HH:mm'
    ),
    source: sourceLabel.value,
  });
});

const toggle = async enabled => {
  isSaving.value = true;
  try {
    await store.dispatch('contacts/setMarketingOptOut', {
      id: props.contactId,
      enabled,
    });
    useAlert(
      enabled
        ? t('CONTACT_PANEL.MARKETING_OPT_OUT.TURNED_ON')
        : t('CONTACT_PANEL.MARKETING_OPT_OUT.TURNED_OFF')
    );
  } catch {
    useAlert(t('CONTACT_PANEL.MARKETING_OPT_OUT.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full gap-1 px-3 py-2.5 border rounded-lg"
    :class="isOptedOut ? 'border-n-ruby-6 bg-n-ruby-2' : 'border-n-weak'"
  >
    <div class="flex items-center justify-between gap-2">
      <label
        :for="`marketing-opt-out-${contactId}`"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t('CONTACT_PANEL.MARKETING_OPT_OUT.TITLE') }}
      </label>
      <Switch
        :id="`marketing-opt-out-${contactId}`"
        :model-value="isOptedOut"
        :disabled="isSaving"
        @update:model-value="toggle"
      />
    </div>
    <p
      class="mb-0 text-xs"
      :class="isOptedOut ? 'text-n-ruby-11' : 'text-n-slate-11'"
    >
      {{ description }}
    </p>
  </div>
</template>
