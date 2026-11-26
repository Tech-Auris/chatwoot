<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';
import Banner from 'dashboard/components/ui/Banner.vue';

// "Este número não tem WhatsApp" on a conversation whose number a lookup found without
// WhatsApp. Dated, because it is one lookup's answer. The server clears the flag when the
// contact writes or a message is delivered, and pushes the change.
const props = defineProps({
  // Unix seconds, or null when there is nothing to warn about.
  checkedAt: { type: Number, default: null },
});

const { t } = useI18n();

const message = computed(() =>
  t('CONVERSATION.WHATSAPP_NUMBER_MISSING_BANNER', {
    date: format(new Date(props.checkedAt * 1000), 'dd/MM/yyyy HH:mm'),
  })
);
</script>

<template>
  <Banner
    v-if="checkedAt"
    color-scheme="warning"
    class="mt-2 mx-2 rounded-lg overflow-hidden"
    :banner-message="message"
  />
</template>
