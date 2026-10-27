<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxReconnectionRequired from '../../components/InboxReconnectionRequired.vue';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { setupFacebookSdk } from './utils';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  whatsappRegistrationIncomplete: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();

const isRequestingAuthorization = ref(false);
const isLoadingFacebook = ref(true);

const whatsappAppId = computed(() => window.chatwootConfig.whatsappAppId);
const whatsappConfigurationId = computed(
  () => window.chatwootConfig.whatsappConfigurationId
);

const actionLabel = computed(() => {
  if (props.whatsappRegistrationIncomplete) {
    return t('INBOX_MGMT.COMPLETE_REGISTRATION');
  }
  return '';
});

const description = computed(() => {
  if (props.whatsappRegistrationIncomplete) {
    return t('INBOX_MGMT.WHATSAPP_REGISTRATION_INCOMPLETE');
  }
  return '';
});

const reauthorizeWhatsApp = async params => {
  isRequestingAuthorization.value = true;

  try {
    const response = await whatsappChannel.postEmbeddedSignupAuthorization({
      inboxId: props.inbox.id,
      ...params,
    });

    if (response.data.success) {
      useAlert(t('INBOX.REAUTHORIZE.SUCCESS'));
    } else {
      useAlert(response.data.message || t('INBOX.REAUTHORIZE.ERROR'));
    }
  } catch (error) {
    useAlert(error.message || t('INBOX.REAUTHORIZE.ERROR'));
  } finally {
    isRequestingAuthorization.value = false;
  }
};

// What the user picked in Meta's popup wins: a number moved to another WABA
// (e.g. a new phone) comes back with new IDs, and resending the stored ones
// would point the inbox at a WABA that no longer exists. The stored number ID
// only fills in when the popup leaves it out for the same WABA.
const reauthorizationParams = signup => {
  const stored = props.inbox.provider_config || {};
  const sameWaba = signup.waba_id === stored.business_account_id;
  return {
    ...signup,
    phone_number_id:
      signup.phone_number_id || (sameWaba && stored.phone_number_id) || '',
  };
};

const handleLoginAndReauthorize = async () => {
  // Validate required configuration
  if (!whatsappAppId.value) {
    throw new Error('WhatsApp App ID is required');
  }
  if (!whatsappConfigurationId.value) {
    throw new Error('WhatsApp Configuration ID is required');
  }

  const signup = await runEmbeddedSignup();
  if (!signup) {
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'));
    return;
  }

  await reauthorizeWhatsApp(reauthorizationParams(signup));
};

const requestAuthorization = async () => {
  if (isLoadingFacebook.value) {
    useAlert(t('INBOX.REAUTHORIZE.LOADING_FACEBOOK'));
    return;
  }

  isRequestingAuthorization.value = true;
  try {
    await handleLoginAndReauthorize();
  } catch (error) {
    useAlert(error.message || t('INBOX.REAUTHORIZE.CONFIGURATION_ERROR'));
  } finally {
    isRequestingAuthorization.value = false;
  }
};

onMounted(async () => {
  try {
    // Validate required configuration
    if (!whatsappAppId.value) {
      useAlert(t('INBOX.REAUTHORIZE.WHATSAPP_APP_ID_MISSING'));
      return;
    }
    if (!whatsappConfigurationId.value) {
      useAlert(t('INBOX.REAUTHORIZE.WHATSAPP_CONFIG_ID_MISSING'));
      return;
    }

    // Load Facebook SDK and initialize
    await setupFacebookSdk(
      whatsappAppId.value,
      window.chatwootConfig?.whatsappApiVersion
    );
  } catch (error) {
    useAlert(t('INBOX.REAUTHORIZE.FACEBOOK_LOAD_ERROR'));
  } finally {
    isLoadingFacebook.value = false;
  }
});

// Expose requestAuthorization function for parent components
defineExpose({
  requestAuthorization,
});
</script>

<template>
  <InboxReconnectionRequired
    class="mx-6"
    :is-loading="isRequestingAuthorization"
    :action-label="actionLabel"
    :description="description"
    @reauthorize="requestAuthorization"
  />
</template>
