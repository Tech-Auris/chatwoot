<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const isRotating = ref(false);

const rotateWebhookToken = async () => {
  isRotating.value = true;
  try {
    await WhatsappChannel.rotateZapiWebhookToken(props.inbox.id);
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.SUCCESS'));
  } catch {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.ERROR'));
  } finally {
    isRotating.value = false;
  }
};
</script>

<template>
  <SettingsSection
    :title="t('INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.TITLE')"
    :sub-title="t('INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.HELP')"
  >
    <NextButton
      class="w-fit"
      data-test-id="rotate-zapi-webhook-token"
      :is-loading="isRotating"
      :disabled="isRotating"
      @click="rotateWebhookToken"
    >
      {{ t('INBOX_MGMT.SETTINGS_POPUP.ZAPI_WEBHOOK_TOKEN.BUTTON') }}
    </NextButton>
  </SettingsSection>
</template>
