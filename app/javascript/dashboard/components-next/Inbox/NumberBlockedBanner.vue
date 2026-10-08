<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { sendBlockReason } from 'dashboard/helper/whatsappHealth';

// Why messages cannot go out of this number right now, and what to do.
// Renders nothing while the number can send.
const props = defineProps({
  inbox: {
    type: Object,
    default: null,
  },
  startsConversation: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const reason = computed(() =>
  sendBlockReason(props.inbox, { startsConversation: props.startsConversation })
);
</script>

<template>
  <div
    v-if="reason"
    role="alert"
    class="flex flex-col gap-1 mx-2 mb-2 px-3 py-2 rounded-lg bg-n-ruby-3 text-sm text-n-ruby-11"
  >
    <span>{{
      t(`COMPOSE_NEW_CONVERSATION.FORM.INBOX_BLOCKED.${reason}`)
    }}</span>
  </div>
</template>
