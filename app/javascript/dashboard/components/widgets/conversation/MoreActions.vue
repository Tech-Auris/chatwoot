<script setup>
import { computed, onUnmounted } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { emitter } from 'shared/helpers/mitt';

import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

const store = useStore();
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);

const currentChat = computed(() => store.getters.getSelectedChat);
const isMuted = computed(() => currentChat.value.muted);
const isContactSidebarOpen = computed(
  () => uiSettings.value.is_contact_sidebar_open
);

const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

const toggleMute = () => (isMuted.value ? unmute() : mute());

// Auris: kept the PDF-download route from the old kebab (this fork skips
// upstream's "send transcript by email" flow because our installs have no
// SMTP; the email UI would silently fail).
const downloadTranscript = async () => {
  try {
    await store.dispatch(
      'downloadConversationTranscriptPdf',
      currentChat.value.id
    );
  } catch (error) {
    const status = error?.response?.status;
    if (status === 429) {
      useAlert(t('CONTACT_PANEL.DOWNLOAD_TRANSCRIPT_OVERLOADED'));
    } else {
      useAlert(t('CONTACT_PANEL.DOWNLOAD_TRANSCRIPT_FAILED'));
    }
  }
};

// Same behaviour as the (now hidden) SidepanelSwitch contact toggle:
// open the contact panel and always close the copilot panel — the two
// panels share the same rail on the right.
const toggleContactSidebar = () => {
  updateUISettings({
    is_contact_sidebar_open: !isContactSidebarOpen.value,
    is_copilot_panel_open: false,
  });
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="flex items-center gap-1 actions--container">
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <Button
      v-tooltip.top="
        isMuted
          ? t('CONTACT_PANEL.UNMUTE_CONTACT')
          : t('CONTACT_PANEL.MUTE_CONTACT')
      "
      size="sm"
      variant="ghost"
      color="slate"
      :icon="isMuted ? 'i-lucide-volume-1' : 'i-lucide-volume-off'"
      class="rounded-md"
      @click="toggleMute"
    />
    <Button
      v-tooltip.top="t('CONTACT_PANEL.DOWNLOAD_TRANSCRIPT')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-download"
      class="rounded-md"
      @click="downloadTranscript"
    />
    <Button
      v-tooltip.top="t('CONVERSATION.SIDEBAR.CONTACT')"
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-ph-user-bold"
      class="rounded-md"
      :class="[isContactSidebarOpen ? 'bg-n-alpha-2 text-n-slate-12' : '']"
      @click="toggleContactSidebar"
    />
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
  </div>
</template>
