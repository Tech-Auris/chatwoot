<script setup>
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useEmitter } from 'dashboard/composables/emitter';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import wootConstants from 'dashboard/constants/globals';
import {
  CMD_REOPEN_CONVERSATION,
  CMD_RESOLVE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

import Button from 'dashboard/components-next/button/Button.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
const { checkMissingAttributes } = useConversationRequiredAttributes();

const isLoading = ref(false);
const resolveAttributesModalRef = ref(null);

const currentChat = computed(() => getters.getSelectedChat.value);

const isOpen = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.OPEN
);
const isPending = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.PENDING
);
const isResolved = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.RESOLVED
);
const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

// Only in the two "active" states does it make sense to show the snooze
// and mark-pending shortcuts — a pending / snoozed conversation lives on
// the single "reopen" affordance.
const showAdditionalActions = computed(
  () => !isPending.value && !isSnoozed.value
);

const showOpenButton = computed(() => isPending.value || isSnoozed.value);

const getConversationParams = () => {
  const allConversations = document.querySelectorAll(
    '.conversations-list .conversation'
  );

  const activeConversation = document.querySelector(
    'div.conversations-list div.conversation.active'
  );
  const activeConversationIndex = [...allConversations].indexOf(
    activeConversation
  );
  const lastConversationIndex = allConversations.length - 1;

  return {
    all: allConversations,
    activeIndex: activeConversationIndex,
    lastIndex: lastConversationIndex,
  };
};

const openSnoozeModal = () => {
  const ninja = document.querySelector('ninja-keys');
  ninja.open({ parent: 'snooze_conversation' });
};

const toggleStatus = (status, snoozedUntil, customAttributes = null) => {
  isLoading.value = true;

  const payload = {
    conversationId: currentChat.value.id,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
    isLoading.value = false;
  });
};

const handleResolveWithAttributes = ({ attributes, context }) => {
  if (context) {
    const currentCustomAttributes = currentChat.value.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };
    toggleStatus(
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
};

const onCmdOpenConversation = () => {
  toggleStatus(wootConstants.STATUS_TYPE.OPEN);
};

const onCmdResolveConversation = () => {
  const currentCustomAttributes = currentChat.value.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    const conversationContext = {
      id: currentChat.value.id,
      snoozedUntil: null,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleStatus(wootConstants.STATUS_TYPE.RESOLVED);
  }
};

const markPending = () => toggleStatus(wootConstants.STATUS_TYPE.PENDING);

const keyboardEvents = {
  // Alt+M previously opened the dropdown for snooze — with the dropdown
  // gone, the shortcut jumps straight to the snooze modal.
  'Alt+KeyM': {
    action: () => openSnoozeModal(),
    allowOnFocusedInput: true,
  },
  'Alt+KeyE': {
    action: () => onCmdResolveConversation(),
  },
  '$mod+Alt+KeyE': {
    action: event => {
      const { all, activeIndex, lastIndex } = getConversationParams();
      onCmdResolveConversation();

      if (activeIndex < lastIndex) {
        all[activeIndex + 1].click();
      } else if (all.length > 1) {
        all[0].click();
        document.querySelector('.conversations-list').scrollTop = 0;
      }
      event.preventDefault();
    },
  },
};

useKeyboardEvents(keyboardEvents);

useEmitter(CMD_REOPEN_CONVERSATION, onCmdOpenConversation);
useEmitter(CMD_RESOLVE_CONVERSATION, onCmdResolveConversation);
</script>

<template>
  <div class="flex items-center gap-1 resolve-actions">
    <!-- Primary status action — check when open (resolve), rotate-ccw when
         resolved (reopen), play when pending/snoozed (return to open). -->
    <Button
      v-if="isOpen"
      v-tooltip.top="t('CONVERSATION.HEADER.RESOLVE_ACTION')"
      icon="i-lucide-check"
      size="sm"
      color="slate"
      variant="ghost"
      :is-loading="isLoading"
      class="rounded-md"
      @click="onCmdResolveConversation"
    />
    <Button
      v-else-if="isResolved"
      v-tooltip.top="t('CONVERSATION.HEADER.REOPEN_ACTION')"
      icon="i-lucide-rotate-ccw"
      size="sm"
      color="slate"
      variant="ghost"
      :is-loading="isLoading"
      class="rounded-md"
      @click="onCmdOpenConversation"
    />
    <Button
      v-else-if="showOpenButton"
      v-tooltip.top="t('CONVERSATION.HEADER.OPEN_ACTION')"
      icon="i-lucide-play"
      size="sm"
      color="slate"
      variant="ghost"
      :is-loading="isLoading"
      class="rounded-md"
      @click="onCmdOpenConversation"
    />
    <Button
      v-if="showAdditionalActions"
      v-tooltip.top="t('CONVERSATION.RESOLVE_DROPDOWN.SNOOZE_UNTIL')"
      icon="i-lucide-alarm-clock-minus"
      size="sm"
      color="slate"
      variant="ghost"
      :disabled="isLoading"
      class="rounded-md"
      @click="openSnoozeModal"
    />
    <Button
      v-if="showAdditionalActions"
      v-tooltip.top="t('CONVERSATION.RESOLVE_DROPDOWN.MARK_PENDING')"
      icon="i-lucide-circle-dot-dashed"
      size="sm"
      color="slate"
      variant="ghost"
      :disabled="isLoading"
      class="rounded-md"
      @click="markPending"
    />
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>
