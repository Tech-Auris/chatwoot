<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';
import { useMapGetter } from 'dashboard/composables/store';
import { sendBlockReason } from 'dashboard/helper/whatsappHealth';

defineProps({
  error: { type: String, required: true },
});

const emit = defineEmits(['retry']);

const { orientation, status, createdAt, content, attachments } =
  useMessageContext();

const { t } = useI18n();

// Retrying through a Baileys / Z-API phone that is not connected would only
// fail again: the button stays off, with the reason in its tooltip.
const currentChat = useMapGetter('getSelectedChat');
const getInbox = useMapGetter('inboxes/getInbox');
const retryBlockReason = computed(() =>
  sendBlockReason(getInbox.value(currentChat.value?.inbox_id))
);
const retryBlockedTooltip = computed(() =>
  retryBlockReason.value
    ? t(`COMPOSE_NEW_CONVERSATION.FORM.INBOX_BLOCKED.${retryBlockReason.value}`)
    : ''
);

const canRetry = computed(() => {
  const hasContent = content.value !== null;
  const hasAttachments = attachments.value && attachments.value.length > 0;
  return !hasOneDayPassed(createdAt.value) && (hasContent || hasAttachments);
});
</script>

<template>
  <div class="text-xs text-n-ruby-11 flex items-center gap-1.5">
    <span>{{ t('CHAT_LIST.FAILED_TO_SEND') }}</span>
    <div class="relative group">
      <div
        class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer"
      >
        <Icon
          icon="i-lucide-alert-triangle"
          class="text-n-ruby-11 size-[14px]"
        />
      </div>
      <div
        class="absolute bg-n-alpha-3 px-4 py-3 border rounded-xl border-n-strong text-n-slate-12 bottom-6 w-52 text-xs backdrop-blur-[100px] shadow-[0px_0px_24px_0px_rgba(0,0,0,0.12)] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all break-all"
        :class="{
          'ltr:left-0 rtl:right-0': orientation === ORIENTATION.LEFT,
          'ltr:right-0 rtl:left-0': orientation === ORIENTATION.RIGHT,
        }"
      >
        {{ error }}
      </div>
    </div>
    <span v-if="canRetry" v-tooltip.top="retryBlockedTooltip">
      <button
        type="button"
        :disabled="status !== MESSAGE_STATUS.FAILED || !!retryBlockReason"
        class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
        @click="emit('retry')"
      >
        <Icon icon="i-lucide-refresh-ccw" class="text-n-ruby-11 size-[14px]" />
      </button>
    </span>
  </div>
</template>
