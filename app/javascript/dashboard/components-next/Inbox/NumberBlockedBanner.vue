<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  sendBlockReason,
  metaBlockErrors,
} from 'dashboard/helper/whatsappHealth';

// Why messages cannot go out of this number right now, and what to do. With
// Meta blocking it, Meta's own reason and fix are listed under the message.
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
const errors = computed(() =>
  reason.value === 'META_BLOCKED' ? metaBlockErrors(props.inbox) : []
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
    <span v-for="error in errors" :key="error.error_code" class="text-xs">
      {{ error.error_description }}
      <template v-if="error.possible_solution">
        {{ t('INBOX_MGMT.ACCOUNT_HEALTH.FIELDS.SEND_STATUS.SOLUTION') }}:
        {{ error.possible_solution }}
      </template>
    </span>
  </div>
</template>
