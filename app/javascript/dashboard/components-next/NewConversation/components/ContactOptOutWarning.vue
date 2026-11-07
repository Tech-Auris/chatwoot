<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';

// Warns before sending that the picked contact asked not to get marketing
// (marketing opt-out). It doesn't block the send: manual messages still go
// out. A contact from the search comes camelCased, while one opened from the
// contact page is the store's snake_case record, so both shapes are read.
const props = defineProps({
  contact: { type: Object, default: null },
});

const { t } = useI18n();

const optOut = computed(() => {
  const contact = props.contact || {};
  return {
    enabled: !!(contact.marketingOptOut ?? contact.marketing_opt_out),
    at: contact.marketingOptOutAt ?? contact.marketing_opt_out_at,
    source: contact.marketingOptOutSource ?? contact.marketing_opt_out_source,
  };
});

const sourceLabel = computed(
  () =>
    ({
      manual: t('CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.MANUAL'),
      meta: t('CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.META'),
      template_button: t(
        'CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.TEMPLATE_BUTTON'
      ),
      ai: t('CONTACT_PANEL.MARKETING_OPT_OUT.SOURCE.AI'),
    })[optOut.value.source]
);

const since = computed(() => {
  if (!optOut.value.at) return sourceLabel.value;
  return t('CONTACT_PANEL.MARKETING_OPT_OUT.ON_SINCE', {
    date: format(new Date(optOut.value.at * 1000), 'dd/MM/yyyy HH:mm'),
    source: sourceLabel.value,
  });
});
</script>

<template>
  <div v-if="optOut.enabled" class="px-4 py-3">
    <div
      role="alert"
      class="flex flex-col gap-0.5 px-3 py-2 rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      <span class="text-sm font-medium">
        {{ t('COMPOSE_NEW_CONVERSATION.FORM.MARKETING_OPT_OUT_WARNING') }}
      </span>
      <span v-if="since" class="text-xs">{{ since }}</span>
    </div>
  </div>
  <span v-else class="hidden" />
</template>
