<script setup>
/* global axios */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import InboxStatusBadge from 'dashboard/components-next/Inbox/InboxStatusBadge.vue';
import { sendBlockReason } from 'dashboard/helper/whatsappHealth';
import WhatsappConnectionBanner from 'dashboard/components-next/Inbox/WhatsappConnectionBanner.vue';

// "Para" and "Via" rows of the schedule form, shown when it is opened outside
// a conversation (Mensagens agendadas). Same shape as the pencil's pickers:
// Via shows each number's status, and a number with a problem only gets a
// warning — the message goes out later, and the number may be back by then.
defineProps({
  hasError: {
    type: Boolean,
    default: false,
  },
});

const contact = defineModel('contact', { type: Object, default: null });
const inboxId = defineModel('inboxId', { type: Number, default: null });

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
// Already limited to the inboxes the user can see (agents: their own).
const myInboxes = useMapGetter('inboxes/getInboxes');

const contactQuery = ref('');
const contactResults = ref([]);
const contactSearchLoading = ref(false);
const showInboxDropdown = ref(false);

// Before a contact is picked, every inbox of the user; after, only the ones
// the contact is on (the server refuses the others).
const inboxOptions = computed(() => {
  const inboxes = myInboxes.value || [];
  if (!contact.value) return inboxes;

  const contactInboxIds = new Set(
    (contact.value.contact_inboxes || []).map(ci => ci.inbox?.id)
  );
  return inboxes.filter(inbox => contactInboxIds.has(inbox.id));
});

const findInbox = id => (myInboxes.value || []).find(i => i.id === id);
const selectedInbox = computed(() => findInbox(inboxId.value));

const inboxLabel = inbox =>
  inbox.phone_number ? `${inbox.name} (${inbox.phone_number})` : inbox.name;

const contactLabel = computed(() => {
  const c = contact.value;
  if (!c) return '';
  const detail = c.email || c.phone_number;
  if (!detail) return c.name || '';
  return c.name ? `${c.name} (${detail})` : detail;
});

const inboxMenuItems = computed(() =>
  inboxOptions.value.map(inbox => ({
    label: inboxLabel(inbox),
    value: inbox.id,
    action: 'inbox',
  }))
);

// A disconnected Baileys / Z-API number gets the connection banner instead.
const inboxWarning = computed(() => {
  if (['baileys', 'zapi'].includes(selectedInbox.value?.provider)) return '';
  const reason = sendBlockReason(selectedInbox.value);
  return reason
    ? t(`COMPOSE_NEW_CONVERSATION.FORM.INBOX_BLOCKED.${reason}`)
    : '';
});

let searchTimer = null;
watch(contactQuery, value => {
  const query = value.trim();
  clearTimeout(searchTimer);
  if (query.length < 2) {
    contactResults.value = [];
    return;
  }
  searchTimer = setTimeout(async () => {
    contactSearchLoading.value = true;
    try {
      const res = await axios.get(
        `/api/v1/accounts/${accountId.value}/contacts/search`,
        { params: { q: query, include: 'contact_inboxes' } }
      );
      contactResults.value = res.data?.payload || [];
    } catch {
      contactResults.value = [];
    } finally {
      contactSearchLoading.value = false;
    }
  }, 300);
});

const pickContact = picked => {
  contact.value = picked;
  contactQuery.value = '';
  contactResults.value = [];
  // Keeps an inbox picked first when the contact is on it; otherwise picks
  // the only one possible, or none.
  const options = inboxOptions.value;
  if (options.some(inbox => inbox.id === inboxId.value)) return;
  inboxId.value = options.length === 1 ? options[0].id : null;
};

const clearContact = () => {
  contact.value = null;
  inboxId.value = null;
};

const pickInbox = ({ value }) => {
  inboxId.value = value;
  showInboxDropdown.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="relative">
      <div class="flex items-center gap-3 min-h-8">
        <span class="w-8 text-sm font-medium text-n-slate-12">
          {{ t('SCHEDULED.NEW.CONTACT_LABEL') }}
        </span>
        <div
          v-if="contact"
          class="flex items-center gap-1 rounded-md bg-n-alpha-2 pl-3 pr-1 h-7 min-w-0"
        >
          <span class="text-sm truncate text-n-slate-12">
            {{ contactLabel }}
          </span>
          <button
            type="button"
            class="!p-0 w-5 h-5 inline-flex items-center justify-center rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
            :title="t('SCHEDULED.NEW.CLEAR_CONTACT')"
            @click="clearContact"
          >
            <span class="i-lucide-x size-3.5" />
          </button>
        </div>
        <input
          v-else
          v-model="contactQuery"
          type="text"
          :placeholder="t('SCHEDULED.NEW.CONTACT_PLACEHOLDER')"
          class="flex-1 min-w-0 !mb-0 rounded-md px-3 h-8 text-sm"
          :class="{ '!border-n-ruby-9': hasError && !contact }"
        />
      </div>
      <ul
        v-if="!contact && contactResults.length"
        class="absolute z-20 left-11 right-0 mt-1 max-h-56 overflow-y-auto rounded-md border border-n-weak bg-n-solid-1 shadow-lg"
      >
        <li
          v-for="result in contactResults"
          :key="result.id"
          class="px-3 py-2 text-sm cursor-pointer hover:bg-n-alpha-2"
          @click="pickContact(result)"
        >
          <div class="text-n-slate-12">
            {{ result.name || t('SCHEDULED.NO_CONTACT_NAME') }}
          </div>
          <div class="text-xs text-n-slate-11">
            {{ result.phone_number || result.email }}
          </div>
        </li>
      </ul>
      <p
        v-else-if="!contact && contactSearchLoading"
        class="mt-1 mb-0 ml-11 text-xs text-n-slate-11"
      >
        {{ t('SCHEDULED.NEW.SEARCHING') }}
      </p>
    </div>

    <div class="flex items-center gap-3 min-h-8">
      <span class="w-8 text-sm font-medium text-n-slate-12">
        {{ t('SCHEDULED.NEW.INBOX_LABEL') }}
      </span>
      <div
        v-if="selectedInbox"
        class="flex items-center gap-1.5 rounded-md bg-n-alpha-2 pl-3 pr-1 h-7 min-w-0"
      >
        <span class="text-sm truncate text-n-slate-12">
          {{ inboxLabel(selectedInbox) }}
        </span>
        <InboxStatusBadge :inbox="selectedInbox" labeled />
        <button
          type="button"
          class="!p-0 w-5 h-5 inline-flex items-center justify-center rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
          @click="inboxId = null"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <div
        v-else-if="inboxOptions.length"
        v-on-click-outside="() => (showInboxDropdown = false)"
        class="relative flex items-center h-7"
      >
        <button
          type="button"
          class="!p-0 text-sm hover:text-n-slate-12"
          :class="hasError ? 'text-n-ruby-11' : 'text-n-slate-11'"
          @click="showInboxDropdown = !showInboxDropdown"
        >
          {{ t('SCHEDULED.NEW.INBOX_PLACEHOLDER') }}
        </button>
        <DropdownMenu
          v-if="showInboxDropdown"
          :menu-items="inboxMenuItems"
          class="ltr:left-0 rtl:right-0 z-[100] top-8 max-h-56 w-fit max-w-lg dark:!outline-n-slate-5"
          @action="pickInbox"
        >
          <template #trailing-icon="{ item }">
            <InboxStatusBadge
              class="ltr:ml-auto rtl:mr-auto ltr:pl-2 rtl:pr-2"
              :inbox="findInbox(item.value)"
              labeled
            />
          </template>
        </DropdownMenu>
      </div>
      <p v-else-if="contact" class="mb-0 text-xs text-n-amber-11">
        {{ t('SCHEDULED.NEW.INBOX_UNREACHABLE') }}
      </p>
    </div>
    <WhatsappConnectionBanner :inbox="selectedInbox" />
    <p
      v-if="inboxWarning"
      class="mb-0 rounded-md bg-n-amber-3 px-3 py-2 text-xs text-n-amber-11"
    >
      {{ inboxWarning }}
      {{ t('SCHEDULED.NEW.INBOX_WARNING') }}
    </p>
  </div>
</template>
