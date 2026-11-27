<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { sendBlockReason } from 'dashboard/helper/whatsappHealth';
import { isSendStalled } from 'dashboard/helper/whatsapp';
import Banner from 'dashboard/components/ui/Banner.vue';
import WhatsappLinkDeviceModal from 'dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue';

// "WhatsApp não está conectado" for a Baileys / Z-API number, with the way to
// connect it right there: the QR code for admins and managers, a reconnect
// attempt for everyone else. Official numbers only show their status badges.
// Also "conectado, mas não consegue enviar" while baileys-api reports a send
// stall: admins and managers get the modal (disconnect and re-pair); agents get
// no action, since a reconnect on a live socket changes nothing.
// Renders nothing while the number is connected and sending.
const props = defineProps({
  inbox: {
    type: Object,
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();
const { isAdmin, isManager } = useAdmin();

const showLinkDeviceModal = ref(false);

const canManageConnection = computed(() => isAdmin.value || isManager.value);

const isDisconnected = computed(() => Boolean(sendBlockReason(props.inbox)));

const isStalled = computed(() =>
  isSendStalled(
    props.inbox?.provider_connection?.send_stall,
    props.inbox?.provider_connection?.connection
  )
);

const bannerMessage = computed(() => {
  if (isStalled.value) {
    return canManageConnection.value
      ? t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.SEND_STALL')
      : t(
          'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.SEND_STALL_CONTACT_ADMIN'
        );
  }
  return canManageConnection.value
    ? t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED')
    : t(
        'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED_CONTACT_ADMIN'
      );
});

const reconnect = () =>
  store.dispatch('inboxes/setupChannelProvider', props.inbox.id).catch(() => {
    useAlert(
      t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.RECONNECT_FAILED')
    );
  });

const onAction = () => {
  if (canManageConnection.value) {
    showLinkDeviceModal.value = true;
  } else {
    reconnect();
  }
};
</script>

<template>
  <div v-if="isDisconnected || isStalled">
    <WhatsappLinkDeviceModal
      v-if="showLinkDeviceModal"
      :show="showLinkDeviceModal"
      :on-close="() => (showLinkDeviceModal = false)"
      :inbox="inbox"
    />
    <Banner
      color-scheme="alert"
      class="rounded-lg overflow-hidden"
      :banner-message="bannerMessage"
      :has-action-button="canManageConnection || !isStalled"
      :action-button-label="
        canManageConnection
          ? t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.LINK_DEVICE')
          : ''
      "
      :action-button-icon="canManageConnection ? '' : 'i-lucide-refresh-cw'"
      @primary-action="onAction"
    />
  </div>
</template>
