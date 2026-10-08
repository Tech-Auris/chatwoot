<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { sendBlockReason } from 'dashboard/helper/whatsappHealth';
import Banner from 'dashboard/components/ui/Banner.vue';
import WhatsappLinkDeviceModal from 'dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue';

// "WhatsApp não está conectado" for a Baileys / Z-API number, with the way to
// connect it right there: the QR code for admins and managers, a reconnect
// attempt for everyone else. Official numbers only show their status badges.
// Renders nothing while the number is connected.
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
  <div v-if="isDisconnected">
    <WhatsappLinkDeviceModal
      v-if="showLinkDeviceModal"
      :show="showLinkDeviceModal"
      :on-close="() => (showLinkDeviceModal = false)"
      :inbox="inbox"
    />
    <Banner
      color-scheme="alert"
      class="rounded-lg overflow-hidden"
      :banner-message="
        canManageConnection
          ? t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED')
          : t(
              'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED_CONTACT_ADMIN'
            )
      "
      has-action-button
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
