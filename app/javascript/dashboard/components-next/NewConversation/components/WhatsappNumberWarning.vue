<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import InboxesAPI from 'dashboard/api/inboxes';
import { canCheckWhatsappNumber } from 'dashboard/helper/whatsapp';

// Warns, before sending, that the picked contact's number has no WhatsApp on a Baileys
// inbox. It doesn't block the send. Only an explicit "no" warns: a failed or slow lookup
// is "unknown". A contact from the search comes camelCased, while one opened from the
// contact page is the store's snake_case record, so both shapes are read.
const props = defineProps({
  targetInbox: { type: Object, default: null },
  selectedContact: { type: Object, default: null },
});

const { t } = useI18n();

const isMissing = ref(false);

const phoneOf = contact => contact?.phoneNumber || contact?.phone_number || '';

let lookupId = 0;
watch(
  () => [props.targetInbox?.id, phoneOf(props.selectedContact)],
  async () => {
    lookupId += 1;
    const currentLookup = lookupId;
    isMissing.value = false;
    const phoneNumber = phoneOf(props.selectedContact);
    if (!phoneNumber || !canCheckWhatsappNumber(props.targetInbox)) return;

    try {
      const { data } = await InboxesAPI.checkWhatsappNumber(
        props.targetInbox.id,
        phoneNumber
      );
      if (currentLookup === lookupId) isMissing.value = data?.exists === false;
    } catch {
      // Unknown is not "no".
    }
  },
  { immediate: true }
);
</script>

<template>
  <div v-if="isMissing" class="px-4 py-3">
    <div
      role="alert"
      class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      <span class="i-lucide-triangle-alert size-4 shrink-0" />
      <span class="text-sm font-medium">
        {{ t('COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_NUMBER_MISSING') }}
      </span>
    </div>
  </div>
  <span v-else class="hidden" />
</template>
