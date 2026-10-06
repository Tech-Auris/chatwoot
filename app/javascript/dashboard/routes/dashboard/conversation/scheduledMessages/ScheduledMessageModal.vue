<script setup>
/* global axios */
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FileUpload from 'vue-upload-component';

import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useFileUpload } from 'dashboard/composables/useFileUpload';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';
import { MESSAGE_MAX_LENGTH } from 'shared/helpers/MessageTypeHelper';

import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AttachmentPreviews from 'dashboard/components-next/NewConversation/components/AttachmentPreviews.vue';
import DropdownContainer from 'next/dropdown-menu/base/DropdownContainer.vue';
import DropdownBody from 'next/dropdown-menu/base/DropdownBody.vue';
import DropdownSection from 'next/dropdown-menu/base/DropdownSection.vue';
import DropdownItem from 'next/dropdown-menu/base/DropdownItem.vue';
import WhatsappTemplates from 'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ScheduleDateShortcuts from './ScheduleDateShortcuts.vue';
import ScheduledMessageRecipient from './ScheduledMessageRecipient.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import RecurrenceDropdown from './RecurrenceDropdown.vue';
import RecurrenceCustomModal from './RecurrenceCustomModal.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  // Without a conversation (Mensagens agendadas), the form asks for the
  // contact and the inbox ("Para" / "Via") and finds the conversation itself
  // when saving.
  conversationId: {
    type: [Number, String],
    default: null,
  },
  inboxId: {
    type: [Number, String],
    default: null,
  },
  scheduledMessage: {
    type: Object,
    default: null,
  },
  initialContent: {
    type: String,
    default: '',
  },
  initialAttachment: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['update:show', 'close', 'scheduledMessageCreated']);

const { t } = useI18n();
const store = useStore();

const inboxGetter = useMapGetter('inboxes/getInbox');
const uiFlags = useMapGetter('scheduledMessages/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');

const picksRecipient = computed(() => !props.conversationId);
const pickedContact = ref(null);
const pickedInboxId = ref(null);
const recipientError = ref(false);
const isResolvingConversation = ref(false);
const inboxId = computed(() => props.inboxId || pickedInboxId.value);

const isEditing = computed(() => !!props.scheduledMessage?.id);
const isEditingRecurring = computed(
  () =>
    isEditing.value &&
    String(props.scheduledMessage?.id).startsWith('recurring-')
);
const isCreating = computed(() => uiFlags.value.isCreating);
const isUpdating = computed(() => uiFlags.value.isUpdating);
const isSubmitting = computed(
  () => isCreating.value || isUpdating.value || isResolvingConversation.value
);
const currentInbox = computed(() => inboxGetter.value(inboxId.value));

const whatsAppTemplates = computed(() => {
  return store.getters['inboxes/getWhatsAppTemplates'](inboxId.value) || [];
});

// Official API numbers only send approved templates, like the pencil: the
// message field waits for one. A message already saved as free text keeps
// its editor when edited.
const isWhatsappCloudInbox = computed(() => {
  const inbox = currentInbox.value;
  if (inbox?.channel_type !== INBOX_TYPES.WHATSAPP) return false;
  return !['baileys', 'zapi'].includes(inbox.provider);
});
const templateOnly = computed(
  () => isWhatsappCloudInbox.value && !isEditing.value
);

const showWhatsappTemplates = computed(() => {
  return whatsAppTemplates.value.length > 0;
});

const messageContent = ref('');
const scheduledDateTime = ref(null);
const attachments = ref([]);
const existingAttachment = ref(null);
const templateParams = ref(null);
const showConfirmClose = ref(false);
const showWhatsAppTemplatesModal = ref(false);
const contentError = ref(false);
const contentLengthError = ref(false);
const dateTimeError = ref('');
const recurrenceRule = ref(null);
const showRecurrenceCustomModal = ref(false);
const holdOnReply = ref(false);

// Original values for change detection
const originalContent = ref('');
const originalScheduledAt = ref(null);
const originalHasAttachment = ref(false);
const originalHoldOnReply = ref(false);

// NOTE: Local ref to control modal visibility, prevents auto-close when unsaved changes exist
const localShowModal = ref(false);

const removedExistingAttachment = ref(false);

const resetForm = () => {
  messageContent.value = '';
  scheduledDateTime.value = null;
  attachments.value = [];
  existingAttachment.value = null;
  removedExistingAttachment.value = false;
  templateParams.value = null;
  contentError.value = false;
  dateTimeError.value = '';
  recurrenceRule.value = null;
  holdOnReply.value = false;
  pickedContact.value = null;
  pickedInboxId.value = null;
  recipientError.value = false;
  // Reset original values
  originalContent.value = '';
  originalScheduledAt.value = null;
  originalHasAttachment.value = false;
  originalHoldOnReply.value = false;
};

const setFormFromMessage = scheduledMessage => {
  if (!scheduledMessage) {
    resetForm();
    return;
  }

  messageContent.value = scheduledMessage.content || '';
  templateParams.value = scheduledMessage.template_params || null;
  existingAttachment.value = scheduledMessage.attachment || null;
  attachments.value = [];
  recurrenceRule.value = scheduledMessage.recurrence_rule || null;
  holdOnReply.value = scheduledMessage.hold_on_reply || false;

  if (scheduledMessage.scheduled_at) {
    const dateValue = new Date(scheduledMessage.scheduled_at * 1000);
    dateValue.setSeconds(0, 0);
    scheduledDateTime.value = dateValue;
  } else {
    scheduledDateTime.value = null;
  }

  // Store original values for change detection
  originalContent.value = messageContent.value?.trim() || '';
  originalScheduledAt.value = scheduledDateTime.value
    ? new Date(scheduledDateTime.value)
    : null;
  originalHasAttachment.value = !!existingAttachment.value;
  originalHoldOnReply.value = holdOnReply.value;
};

// Read at upload time, so it follows the inbox picked in "Via".
const uploadInbox = reactive({});
watch(
  currentInbox,
  inbox =>
    Object.assign(uploadInbox, {
      channel_type: inbox?.channel_type,
      medium: inbox?.medium,
    }),
  { immediate: true }
);

const { onFileUpload } = useFileUpload({
  inbox: uploadInbox,
  // Direct uploads go through the open conversation; without one, the file
  // travels with the form.
  directUpload: !!props.conversationId,
  attachFile: ({ blob, file }) => {
    if (!file) return;
    const reader = new FileReader();
    reader.readAsDataURL(file.file);
    reader.onloadend = () => {
      attachments.value = [
        {
          resource: blob || file,
          thumb: reader.result,
          blobSignedId: blob?.signed_id,
        },
      ];
    };
  },
});

const scheduledAt = computed(() => {
  if (!scheduledDateTime.value) return null;

  const date = new Date(scheduledDateTime.value);
  date.setSeconds(0, 0);

  return date;
});

const hasContent = computed(() => Boolean(messageContent.value?.trim()));
const hasNewAttachment = computed(() => attachments.value.length > 0);
const hasTemplate = computed(
  () => !!(templateParams.value && Object.keys(templateParams.value).length)
);
const hasExistingAttachment = computed(() => !!existingAttachment.value);
const showAttachmentUpload = computed(
  () =>
    !hasNewAttachment.value &&
    !hasExistingAttachment.value &&
    !hasTemplate.value &&
    !templateOnly.value
);

const displayAttachments = computed(() => {
  if (attachments.value.length) return attachments.value;
  if (existingAttachment.value) {
    return [
      {
        id: existingAttachment.value.id,
        thumb: existingAttachment.value.file_url,
        resource: {
          id: existingAttachment.value.id,
          content_type: existingAttachment.value.file_type,
          filename: existingAttachment.value.filename,
        },
      },
    ];
  }
  return [];
});

const templateName = computed(() => {
  return templateParams.value?.name || templateParams.value?.id || null;
});

const clearTemplate = () => {
  templateParams.value = null;
  messageContent.value = '';
};

const maxLength = computed(() => {
  const channelType = currentInbox.value?.channel_type;
  const medium = currentInbox.value?.medium;

  if (
    channelType === 'Channel::FacebookPage' &&
    medium === 'instagram_direct_message'
  ) {
    return MESSAGE_MAX_LENGTH.INSTAGRAM;
  }
  if (channelType === 'Channel::FacebookPage') {
    return MESSAGE_MAX_LENGTH.FACEBOOK;
  }
  if (channelType === 'Channel::TwilioSms' && medium === 'whatsapp') {
    return MESSAGE_MAX_LENGTH.TWILIO_WHATSAPP;
  }
  if (channelType === 'Channel::Whatsapp') {
    return MESSAGE_MAX_LENGTH.WHATSAPP_CLOUD;
  }
  if (channelType === 'Channel::Sms') {
    return MESSAGE_MAX_LENGTH.TWILIO_SMS;
  }
  if (channelType === 'Channel::TwilioSms' && medium === 'sms') {
    return MESSAGE_MAX_LENGTH.TWILIO_SMS;
  }
  if (channelType === 'Channel::Email') {
    return MESSAGE_MAX_LENGTH.EMAIL;
  }
  if (channelType === 'Channel::Telegram') {
    return MESSAGE_MAX_LENGTH.TELEGRAM;
  }
  if (channelType === 'Channel::Line') {
    return MESSAGE_MAX_LENGTH.LINE;
  }
  if (channelType === 'Channel::Tiktok') {
    return MESSAGE_MAX_LENGTH.TIKTOK;
  }
  return MESSAGE_MAX_LENGTH.GENERAL;
});

const isContentTooLong = computed(
  () => messageContent.value?.length > maxLength.value
);

const hasUnsavedChanges = computed(() => {
  const contentChanged = messageContent.value?.trim() !== originalContent.value;
  const dateChanged =
    scheduledDateTime.value?.getTime() !== originalScheduledAt.value?.getTime();
  const attachmentChanged =
    hasNewAttachment.value ||
    (originalHasAttachment.value && !hasExistingAttachment.value);
  const holdOnReplyChanged = holdOnReply.value !== originalHoldOnReply.value;

  return (
    contentChanged || dateChanged || attachmentChanged || holdOnReplyChanged
  );
});

const showModal = computed({
  get: () => localShowModal.value,
  set: value => {
    // NOTE: When trying to close the modal, check for unsaved changes first
    if (!value && hasUnsavedChanges.value && !showConfirmClose.value) {
      showConfirmClose.value = true;
      return;
    }
    localShowModal.value = value;
    if (!value) {
      emit('update:show', false);
    }
  },
});

watch(
  () => props.show,
  newValue => {
    if (newValue) {
      localShowModal.value = true;
    }
  },
  { immediate: true }
);

const onAttachmentsChange = value => {
  attachments.value = value.slice(0, 1);
};

const onDisplayAttachmentsChange = value => {
  if (value.length === 0) {
    if (existingAttachment.value) removedExistingAttachment.value = true;
    attachments.value = [];
    existingAttachment.value = null;
  } else {
    onAttachmentsChange(value);
  }
};

const resolveAttachmentPayload = () => {
  if (!attachments.value.length) return null;
  const attachment = attachments.value[0];
  return (
    attachment.blobSignedId ||
    attachment.resource?.signed_id ||
    attachment.resource?.file ||
    attachment.resource
  );
};

const isFutureSchedule = date => {
  if (!date) return false;
  const scheduled = new Date(date);
  const now = new Date();
  return scheduled > now;
};

const validatePayload = status => {
  contentError.value = false;
  contentLengthError.value = false;
  dateTimeError.value = '';
  recipientError.value = false;

  if (picksRecipient.value && (!pickedContact.value || !pickedInboxId.value)) {
    recipientError.value = true;
    return false;
  }

  if (templateOnly.value && !hasTemplate.value) {
    contentError.value = true;
    return false;
  }

  const hasPayloadContent =
    hasContent.value ||
    hasTemplate.value ||
    hasExistingAttachment.value ||
    hasNewAttachment.value;

  if (!hasPayloadContent) {
    contentError.value = true;
    return false;
  }

  if (isContentTooLong.value) {
    contentLengthError.value = true;
    return false;
  }

  if (status === 'pending') {
    if (!scheduledAt.value) {
      dateTimeError.value = t('SCHEDULED_MESSAGES.ERRORS.DATETIME_REQUIRED');
      return false;
    }
    if (!isFutureSchedule(scheduledAt.value)) {
      dateTimeError.value = t('SCHEDULED_MESSAGES.ERRORS.SCHEDULE_IN_PAST');
      return false;
    }
  }

  return true;
};

const buildPayload = status => {
  const payload = {
    content: messageContent.value,
    status,
    scheduledAt: scheduledAt.value ? scheduledAt.value.toISOString() : null,
    holdOnReply: holdOnReply.value,
    private: false,
  };

  if (templateParams.value && Object.keys(templateParams.value).length) {
    payload.templateParams = templateParams.value;
  }

  const attachmentPayload = resolveAttachmentPayload();
  if (attachmentPayload) {
    payload.attachment = attachmentPayload;
  } else if (removedExistingAttachment.value) {
    payload.removeAttachment = true;
  }

  return payload;
};

const closeModal = () => {
  showConfirmClose.value = false;
  localShowModal.value = false;
  emit('update:show', false);
  emit('close');
  resetForm();
};

const openWhatsAppTemplatesModal = () => {
  showWhatsAppTemplatesModal.value = true;
};

const hideWhatsAppTemplatesModal = () => {
  showWhatsAppTemplatesModal.value = false;
};

// A template belongs to its inbox: picking another one drops it.
watch(pickedInboxId, () => {
  if (hasTemplate.value) clearTemplate();
});

const onTemplateSelect = messagePayload => {
  templateParams.value = messagePayload.templateParams;
  messageContent.value = messagePayload.message;
  hideWhatsAppTemplatesModal();
  contentError.value = false;
};

// The conversation the message goes to: the open one, or the one for the
// contact and inbox picked in "Para" / "Via" (found or opened on the server).
const resolveConversationId = async () => {
  if (props.conversationId) return props.conversationId;

  isResolvingConversation.value = true;
  try {
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/scheduled_messages/conversation`,
      { contact_id: pickedContact.value.id, inbox_id: pickedInboxId.value }
    );
    return data.conversation_id;
  } finally {
    isResolvingConversation.value = false;
  }
};

const submit = async status => {
  if (!validatePayload(status)) return;

  try {
    const conversationId = await resolveConversationId();
    const hasRecurrence = !!recurrenceRule.value;
    const existingRecurringId =
      props.scheduledMessage?.recurring_scheduled_message_id;

    if (hasRecurrence && status === 'pending') {
      const recurringPayload = {
        content: messageContent.value,
        scheduledAt: scheduledAt.value ? scheduledAt.value.toISOString() : null,
        recurrenceRule: recurrenceRule.value,
        attachment: resolveAttachmentPayload(),
        templateParams: templateParams.value,
        holdOnReply: holdOnReply.value,
        status: 'active',
      };

      if (isEditing.value && existingRecurringId) {
        // Update existing recurring series
        await store.dispatch('recurringScheduledMessages/update', {
          conversationId,
          recurringScheduledMessageId: existingRecurringId,
          payload: recurringPayload,
        });
      } else {
        // Create new recurring series (new message or standalone gaining recurrence)
        await store.dispatch('recurringScheduledMessages/create', {
          conversationId,
          payload: recurringPayload,
        });
        // If converting a standalone message, delete the old one
        if (isEditing.value) {
          await store.dispatch('scheduledMessages/delete', {
            conversationId,
            scheduledMessageId: props.scheduledMessage.id,
          });
        }
      }
    } else if (isEditing.value) {
      // Editing without recurrence - if it had a recurring parent and user removed it, cancel the series
      if (existingRecurringId && !hasRecurrence) {
        await store.dispatch('recurringScheduledMessages/delete', {
          conversationId,
          recurringScheduledMessageId: existingRecurringId,
        });
        // If this was a direct recurring message edit, just close — no standalone to update
        if (isEditingRecurring.value) {
          closeModal();
          return;
        }
      }
      await store.dispatch('scheduledMessages/update', {
        conversationId,
        scheduledMessageId: props.scheduledMessage.id,
        payload: buildPayload(status),
      });
    } else {
      await store.dispatch('scheduledMessages/create', {
        conversationId,
        payload: buildPayload(status),
      });
    }

    if (status === 'pending') {
      emit('scheduledMessageCreated');
    }
    if (picksRecipient.value) useAlert(t('SCHEDULED.NEW.DONE'));
    closeModal();
  } catch (error) {
    useAlert(t('SCHEDULED_MESSAGES.ERRORS.SAVE_FAILED'));
  }
};

const handleClose = () => {
  if (hasUnsavedChanges.value) {
    showConfirmClose.value = true;
    return;
  }
  closeModal();
};

const handleContinueEditing = () => {
  showConfirmClose.value = false;
};

const handleConfirmDiscard = () => {
  showConfirmClose.value = false;
  closeModal();
};

watch(
  () => props.show,
  isVisible => {
    if (isVisible) {
      if (props.scheduledMessage) {
        setFormFromMessage(props.scheduledMessage);
      } else {
        resetForm();
        if (props.initialContent) {
          messageContent.value = props.initialContent;
        }
        if (props.initialAttachment) {
          attachments.value = [
            {
              resource: props.initialAttachment.resource,
              thumb: props.initialAttachment.thumb,
              blobSignedId: props.initialAttachment.blobSignedId,
            },
          ];
        }
      }
    } else {
      resetForm();
    }
  }
);

watch(
  () => props.scheduledMessage,
  newMessage => {
    if (props.show) {
      setFormFromMessage(newMessage);
    }
  }
);
</script>

<template>
  <woot-modal
    v-model:show="showModal"
    close-on-backdrop-click
    class="[&_.modal-container]:!w-[45rem] [&_.modal-container]:!max-w-[90%]"
    size="medium"
    @close="handleClose"
  >
    <div class="flex w-full flex-col gap-6 px-6 py-6">
      <h3 class="text-lg font-semibold text-n-slate-12">
        {{
          isEditing
            ? t('SCHEDULED_MESSAGES.MODAL.TITLE_EDIT')
            : t('SCHEDULED_MESSAGES.MODAL.TITLE_NEW')
        }}
      </h3>

      <ScheduledMessageRecipient
        v-if="picksRecipient"
        v-model:contact="pickedContact"
        v-model:inbox-id="pickedInboxId"
        :has-error="recipientError"
      />

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('SCHEDULED_MESSAGES.MODAL.MESSAGE_LABEL') }}
        </span>
        <div v-if="templateOnly && !hasTemplate" class="flex items-center">
          <NextButton
            icon="i-ri-whatsapp-line"
            :label="t('COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_OPTIONS.LABEL')"
            color="slate"
            size="sm"
            class="!text-xs font-medium"
            @click="openWhatsAppTemplatesModal"
          />
        </div>
        <WootMessageEditor
          v-else
          v-model="messageContent"
          class="message-editor min-h-[10rem] max-h-[20rem] !px-3 resize-y overflow-auto"
          :class="[
            contentError || contentLengthError
              ? 'border border-n-ruby-9 rounded-xl'
              : '',
            hasTemplate ? 'opacity-60 cursor-not-allowed' : '',
          ]"
          :placeholder="t('SCHEDULED_MESSAGES.MODAL.MESSAGE_PLACEHOLDER')"
          :channel-type="currentInbox?.channel_type"
          :medium="currentInbox?.medium"
          :disabled="!!hasTemplate"
          :enable-copilot="false"
          enable-variables
          override-line-breaks
          @update:model-value="
            () => {
              contentError = false;
              contentLengthError = false;
            }
          "
        />
        <span v-if="contentError" class="text-xs text-n-ruby-9">
          {{
            templateOnly
              ? t('SCHEDULED_MESSAGES.ERRORS.TEMPLATE_REQUIRED')
              : t('SCHEDULED_MESSAGES.ERRORS.CONTENT_REQUIRED')
          }}
        </span>
        <span v-if="recipientError" class="text-xs text-n-ruby-9">
          {{ t('SCHEDULED_MESSAGES.ERRORS.RECIPIENT_REQUIRED') }}
        </span>
        <span v-if="contentLengthError" class="text-xs text-n-ruby-9">
          {{
            t('SCHEDULED_MESSAGES.ERRORS.CONTENT_TOO_LONG', {
              maxLength: maxLength,
            })
          }}
        </span>
        <div class="flex items-center gap-2">
          <div v-if="showAttachmentUpload" class="flex items-center gap-2 h-10">
            <FileUpload
              :accept="ALLOWED_FILE_TYPES"
              :multiple="false"
              :maximum="1"
              class="cursor-pointer [&:hover_button]:bg-n-alpha-2 [&:hover_button]:text-n-slate-12"
              @input-file="onFileUpload"
            >
              <NextButton
                ghost
                xs
                icon="i-lucide-paperclip"
                :label="t('SCHEDULED_MESSAGES.MODAL.ATTACHMENT_ADD')"
                class="pointer-events-none"
              />
            </FileUpload>
            <NextButton
              v-if="showWhatsappTemplates"
              ghost
              xs
              icon="i-lucide-zap"
              :label="t('SCHEDULED_MESSAGES.MODAL.TEMPLATE_SELECT')"
              @click="openWhatsAppTemplatesModal"
            />
          </div>
          <div
            v-if="hasTemplate"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span>
              {{
                t('SCHEDULED_MESSAGES.MODAL.TEMPLATE_SELECTED', {
                  name: templateName,
                })
              }}
            </span>
            <NextButton
              ghost
              xs
              slate
              icon="i-lucide-x"
              @click="clearTemplate"
            />
          </div>
          <AttachmentPreviews
            v-if="displayAttachments.length"
            class="!p-0"
            :attachments="displayAttachments"
            @update:attachments="onDisplayAttachmentsChange"
          />
        </div>
      </div>

      <div class="flex flex-col gap-3 min-w-0">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('SCHEDULED_MESSAGES.MODAL.SCHEDULE_LABEL') }}
        </span>
        <ScheduleDateShortcuts
          v-model="scheduledDateTime"
          :date-time-error="dateTimeError"
          @update:model-value="dateTimeError = ''"
        />
        <span v-if="dateTimeError" class="text-xs text-n-ruby-9">
          {{ dateTimeError }}
        </span>
      </div>

      <RecurrenceDropdown
        v-model="recurrenceRule"
        :scheduled-date="scheduledDateTime"
        :hide-no-repeat="isEditingRecurring"
        @open-custom="showRecurrenceCustomModal = true"
      />

      <RecurrenceCustomModal
        :show="showRecurrenceCustomModal"
        :model-value="recurrenceRule"
        :scheduled-date="scheduledDateTime"
        @update:model-value="recurrenceRule = $event"
        @close="showRecurrenceCustomModal = false"
      />

      <div
        class="flex items-start gap-3 rounded-xl border border-n-slate-4 bg-n-slate-2 px-4 py-3"
      >
        <Switch v-model="holdOnReply" class="mt-0.5 shrink-0" />
        <div class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('SCHEDULED_MESSAGES.MODAL.HOLD_ON_REPLY_LABEL') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('SCHEDULED_MESSAGES.MODAL.HOLD_ON_REPLY_DESCRIPTION') }}
          </span>
        </div>
      </div>

      <div class="flex items-center justify-end gap-3">
        <NextButton
          faded
          slate
          :label="t('SCHEDULED_MESSAGES.MODAL.CANCEL')"
          :disabled="isSubmitting"
          @click="handleClose"
        />
        <div class="relative flex">
          <NextButton
            solid
            blue
            :label="t('SCHEDULED_MESSAGES.MODAL.SCHEDULE')"
            :is-loading="isSubmitting"
            :disabled="isSubmitting"
            class="rounded-r-none"
            @click="submit('pending')"
          />
          <DropdownContainer>
            <template #trigger="{ toggle }">
              <NextButton
                solid
                blue
                icon="i-lucide-chevron-down"
                :is-loading="isSubmitting"
                :disabled="isSubmitting"
                class="-ml-px rounded-l-none border-l border-l-white/20"
                @click="toggle"
              />
            </template>
            <template #default>
              <DropdownBody class="bottom-12 -right-10 min-w-[260px] z-[10000]">
                <DropdownSection>
                  <DropdownItem
                    icon="i-lucide-file-text"
                    :label="t('SCHEDULED_MESSAGES.MODAL.SAVE_DRAFT')"
                    @click="submit('draft')"
                  />
                </DropdownSection>
              </DropdownBody>
            </template>
          </DropdownContainer>
        </div>
      </div>
    </div>

    <woot-modal
      v-model:show="showConfirmClose"
      :show-close-button="false"
      size="small"
      @close="() => {}"
    >
      <div class="flex w-full flex-col gap-4 px-6 py-6">
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ t('SCHEDULED_MESSAGES.CONFIRM_CLOSE.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('SCHEDULED_MESSAGES.CONFIRM_CLOSE.MESSAGE') }}
        </p>
        <div class="flex items-center justify-end gap-3">
          <NextButton
            ghost
            slate
            :label="t('SCHEDULED_MESSAGES.CONFIRM_CLOSE.CONTINUE_EDITING')"
            @click="handleContinueEditing"
          />
          <NextButton
            solid
            blue
            :label="t('SCHEDULED_MESSAGES.CONFIRM_CLOSE.DISCARD')"
            @click="handleConfirmDiscard"
          />
        </div>
      </div>
    </woot-modal>

    <WhatsappTemplates
      v-model:show="showWhatsAppTemplatesModal"
      :inbox-id="inboxId"
      :send-button-label="t('SCHEDULED_MESSAGES.MODAL.TEMPLATE_ACTION')"
      @on-send="onTemplateSelect"
      @cancel="hideWhatsAppTemplatesModal"
    />
  </woot-modal>
</template>
