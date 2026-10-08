<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  sendBlockReason,
  sendWarningReason,
} from 'dashboard/helper/whatsappHealth';

// Why messages may not go out of this number right now. Red when sending is
// stopped (a Baileys / Z-API phone not connected), amber when it is only a
// warning (Meta's status on an official number). Renders nothing while the
// number is fine.
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

const options = computed(() => ({
  startsConversation: props.startsConversation,
}));
const reason = computed(() => sendWarningReason(props.inbox, options.value));
const blocks = computed(() =>
  Boolean(sendBlockReason(props.inbox, options.value))
);
</script>

<template>
  <div
    v-if="reason"
    role="alert"
    class="flex flex-col gap-1 mx-2 mb-2 px-3 py-2 rounded-lg text-sm"
    :class="
      blocks ? 'bg-n-ruby-3 text-n-ruby-11' : 'bg-n-amber-3 text-n-amber-11'
    "
  >
    <span>{{
      t(`COMPOSE_NEW_CONVERSATION.FORM.INBOX_BLOCKED.${reason}`)
    }}</span>
  </div>
</template>
