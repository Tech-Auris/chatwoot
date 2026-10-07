<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  sendBlockReason,
  metaBlockErrors,
} from 'dashboard/helper/whatsappHealth';
import Banner from 'dashboard/components/ui/Banner.vue';
import WhatsappLinkDeviceModal from 'dashboard/routes/dashboard/settings/inbox/components/WhatsappLinkDeviceModal.vue';

// Why messages cannot go out of this WhatsApp number right now. A Baileys /
// Z-API number gets the way to connect it right there: the QR code for admins
// and managers, a reconnect attempt for everyone else. An official API number
// gets the reason — Meta's own reason and fix when Meta blocks it. Renders
// nothing while the number can send.
const props = defineProps({
  inbox: {
    type: Object,
    default: null,
  },
  // Opening a new conversation, which a RESTRICTED number cannot do.
  startsConversation: {
    type: Boolean,
    default: false,
  },
});

const store = useStore();
const { t } = useI18n();
const { isAdmin, isManager } = useAdmin();

const showLinkDeviceModal = ref(false);

const canManageConnection = computed(() => isAdmin.value || isManager.value);

const isUnofficial = computed(() =>
  ['baileys', 'zapi'].includes(props.inbox?.provider)
);

const reason = computed(() =>
  sendBlockReason(props.inbox, { startsConversation: props.startsConversation })
);

const metaMessage = computed(() =>
  metaBlockErrors(props.inbox)
    .map(error =>
      error.possible_solution
        ? `${error.error_description} ${t('INBOX_MGMT.ACCOUNT_HEALTH.FIELDS.SEND_STATUS.SOLUTION')}: ${error.possible_solution}`
        : error.error_description
    )
    .join(' ')
);

const message = computed(() => {
  if (isUnofficial.value) {
    return canManageConnection.value
      ? t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED')
      : t(
          'CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.NOT_CONNECTED_CONTACT_ADMIN'
        );
  }
  if (reason.value === 'META_BLOCKED' && metaMessage.value) {
    return metaMessage.value;
  }
  return t(`COMPOSE_NEW_CONVERSATION.FORM.INBOX_BLOCKED.${reason.value}`);
});

const actionLabel = computed(() =>
  isUnofficial.value && canManageConnection.value
    ? t('CONVERSATION.INBOX.WHATSAPP_PROVIDER_CONNECTION.LINK_DEVICE')
    : ''
);

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
  <div v-if="reason">
    <WhatsappLinkDeviceModal
      v-if="showLinkDeviceModal"
      :show="showLinkDeviceModal"
      :on-close="() => (showLinkDeviceModal = false)"
      :inbox="inbox"
    />
    <Banner
      color-scheme="alert"
      class="rounded-lg overflow-hidden"
      :banner-message="message"
      :has-action-button="isUnofficial"
      :action-button-label="actionLabel"
      :action-button-icon="actionLabel ? '' : 'i-lucide-refresh-cw'"
      @primary-action="onAction"
    />
  </div>
</template>
