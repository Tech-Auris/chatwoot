<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { generateLabelForContactableInboxesList } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper.js';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { sendBlockReason } from 'dashboard/helper/whatsappHealth';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import InboxStatusBadge from 'dashboard/components-next/Inbox/InboxStatusBadge.vue';

const props = defineProps({
  targetInbox: {
    type: Object,
    default: null,
  },
  selectedContact: {
    type: Object,
    default: null,
  },
  showInboxesDropdown: {
    type: Boolean,
    required: true,
  },
  contactableInboxesList: {
    type: Array,
    default: () => [],
  },
  hasErrors: {
    type: Boolean,
    default: false,
  },
  isFetchingInboxes: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'updateInbox',
  'toggleDropdown',
  'handleInboxAction',
]);

const { t } = useI18n();

// The contactable inboxes carry no connection data; the inbox store does.
const getInbox = useMapGetter('inboxes/getInbox');

const blockReason = inboxId => sendBlockReason(getInbox.value(inboxId));

// A number that cannot send (disconnected, banned…) stays in the list with
// its status, but picking it explains why instead of selecting it.
const onInboxAction = item => {
  const reason = blockReason(item.value);
  if (reason) {
    useAlert(t(`COMPOSE_NEW_CONVERSATION.FORM.INBOX_BLOCKED.${reason}`));
    return;
  }
  emit('handleInboxAction', item);
};

const targetInboxLabel = computed(() => {
  return generateLabelForContactableInboxesList(props.targetInbox);
});
</script>

<template>
  <div
    class="flex items-center flex-1 w-full gap-3 px-4 py-3 overflow-y-visible"
  >
    <label class="mb-0.5 text-sm font-medium text-n-slate-11 whitespace-nowrap">
      {{ t('COMPOSE_NEW_CONVERSATION.FORM.INBOX_SELECTOR.LABEL') }}
    </label>
    <div
      v-if="targetInbox"
      class="flex items-center gap-1.5 rounded-md bg-n-alpha-2 truncate ltr:pl-3 rtl:pr-3 ltr:pr-1 rtl:pl-1 h-7 min-w-0"
    >
      <span class="text-sm truncate text-n-slate-12">
        {{ targetInboxLabel }}
      </span>
      <InboxStatusBadge :inbox="getInbox(targetInbox.id)" labeled />
      <Button
        variant="ghost"
        icon="i-lucide-x"
        color="slate"
        size="xs"
        class="flex-shrink-0"
        @click="emit('updateInbox', null)"
      />
    </div>
    <div
      v-else
      v-on-click-outside="() => emit('toggleDropdown', false)"
      class="relative flex items-center h-7"
    >
      <Spinner v-if="isFetchingInboxes" :size="16" />
      <Button
        v-else
        :label="t('COMPOSE_NEW_CONVERSATION.FORM.INBOX_SELECTOR.BUTTON')"
        variant="link"
        size="sm"
        :color="hasErrors ? 'ruby' : 'slate'"
        :disabled="!selectedContact"
        class="hover:!no-underline"
        @click="emit('toggleDropdown', !showInboxesDropdown)"
      />
      <DropdownMenu
        v-if="contactableInboxesList?.length > 0 && showInboxesDropdown"
        :menu-items="contactableInboxesList"
        class="ltr:left-0 rtl:right-0 z-[100] top-8 max-h-56 w-fit max-w-lg dark:!outline-n-slate-5"
        @action="onInboxAction"
      >
        <template #label="{ item }">
          <span
            class="min-w-0 text-sm font-420 truncate"
            :class="{ 'opacity-50': blockReason(item.value) }"
          >
            {{ item.label }}
          </span>
        </template>
        <template #trailing-icon="{ item }">
          <InboxStatusBadge
            class="ltr:ml-auto rtl:mr-auto ltr:pl-2 rtl:pr-2"
            :inbox="getInbox(item.value)"
            labeled
          />
        </template>
      </DropdownMenu>
    </div>
  </div>
</template>
