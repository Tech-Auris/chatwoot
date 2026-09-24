<script setup>
/* global axios */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';

// A lean v1 of the composer that lets the operator schedule a message
// from the Agendadas panel without having to open a conversation first.
// Reuses the existing conversation-drawer modal for anything more
// elaborate (rich formatting, attachment, recurrence, WhatsApp
// templates). Two picker rows at the top mirror the "+ Nova mensagem"
// pencil flow so muscle memory carries over.

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:show', 'scheduled']);

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const contactQuery = ref('');
const contactResults = ref([]);
const contactSearchLoading = ref(false);
const selectedContact = ref(null);
const contactInboxes = ref([]);
const selectedInboxId = ref(null);
const message = ref('');
const scheduledAt = ref('');
const holdOnReply = ref(true);
const isSaving = ref(false);

// A fresh contact search fires whenever the operator types >= 2 chars.
// The endpoint is the same one the pencil flow calls; results carry
// `contact_inboxes` inline so we can populate Via without a follow-up.
let searchTimer = null;
watch(contactQuery, value => {
  const query = value.trim();
  if (query.length < 2) {
    contactResults.value = [];
    return;
  }
  clearTimeout(searchTimer);
  searchTimer = setTimeout(async () => {
    contactSearchLoading.value = true;
    try {
      const res = await axios.get(
        `/api/v1/accounts/${accountId.value}/contacts/search`,
        { params: { q: query, include: 'contact_inboxes' } }
      );
      contactResults.value = res.data?.payload || [];
    } catch (e) {
      contactResults.value = [];
    } finally {
      contactSearchLoading.value = false;
    }
  }, 300);
});

const pickContact = contact => {
  selectedContact.value = contact;
  contactQuery.value = contact.name || contact.phone_number || '';
  contactResults.value = [];
  contactInboxes.value = contact.contact_inboxes || [];
  selectedInboxId.value =
    contactInboxes.value.length === 1
      ? contactInboxes.value[0].inbox?.id
      : null;
};

const clearContact = () => {
  selectedContact.value = null;
  contactInboxes.value = [];
  selectedInboxId.value = null;
  contactQuery.value = '';
};

// The three shortcuts mirror what the conversation-drawer modal shows so
// muscle memory holds. Amanhã de manhã = tomorrow 08:00, amanhã à tarde
// = tomorrow 13:00, segunda de manhã = next Monday 08:00. The local
// datetime input carries whatever the operator picked (either a
// shortcut just filled it in, or they typed).
const scheduleShortcuts = computed(() => {
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const morning = new Date(tomorrow);
  morning.setHours(8, 0, 0, 0);
  const afternoon = new Date(tomorrow);
  afternoon.setHours(13, 0, 0, 0);
  const monday = new Date(now);
  const dayShift = (8 - monday.getDay()) % 7 || 7;
  monday.setDate(monday.getDate() + dayShift);
  monday.setHours(8, 0, 0, 0);
  return [
    { id: 'tomorrow-morning', label: 'Amanhã de manhã', date: morning },
    { id: 'tomorrow-afternoon', label: 'Amanhã à tarde', date: afternoon },
    { id: 'monday-morning', label: 'Segunda-feira de manhã', date: monday },
  ].map(entry => ({
    ...entry,
    display: entry.date.toLocaleString('pt-BR', {
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    }),
  }));
});

const applyShortcut = shortcut => {
  // The datetime-local input expects `YYYY-MM-DDTHH:mm` in local time.
  const pad = n => String(n).padStart(2, '0');
  const d = shortcut.date;
  scheduledAt.value =
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const canSubmit = computed(
  () =>
    selectedContact.value &&
    selectedInboxId.value &&
    message.value.trim().length > 0 &&
    !!scheduledAt.value &&
    !isSaving.value
);

const close = () => emit('update:show', false);

const reset = () => {
  clearContact();
  message.value = '';
  scheduledAt.value = '';
  holdOnReply.value = true;
};

const submit = async () => {
  if (!canSubmit.value) return;
  isSaving.value = true;
  try {
    // Convert the local `YYYY-MM-DDTHH:mm` back to an ISO the server can
    // read as UTC without inheriting the app's `Time.zone`.
    const iso = new Date(scheduledAt.value).toISOString();
    await axios.post(`/api/v1/accounts/${accountId.value}/scheduled_messages`, {
      contact_id: selectedContact.value.id,
      inbox_id: selectedInboxId.value,
      content: message.value,
      scheduled_at: iso,
      hold_on_reply: holdOnReply.value,
    });
    useAlert(t('SCHEDULED.NEW.DONE'));
    emit('scheduled');
    reset();
    close();
  } catch (e) {
    useAlert(
      e.response?.data?.errors?.join(', ') ||
        e.message ||
        t('SCHEDULED.NEW.FAILED')
    );
  } finally {
    isSaving.value = false;
  }
};

watch(
  () => props.show,
  value => {
    if (!value) reset();
  }
);
</script>

<template>
  <teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 py-6"
      @click.self="close"
    >
      <div
        class="w-full max-w-lg bg-n-solid-1 rounded-xl shadow-xl flex flex-col max-h-[92vh] overflow-hidden"
      >
        <header class="flex items-start justify-between px-6 pt-5 pb-3">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('SCHEDULED.NEW.TITLE') }}
          </h2>
          <button
            type="button"
            class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :title="t('MEDIA_HUB.CLOSE')"
            @click="close"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </header>

        <div class="flex-1 overflow-y-auto px-6 pb-5 flex flex-col gap-4">
          <!-- Para: contact search -->
          <div>
            <label
              class="text-sm font-medium text-n-slate-12 flex gap-2 items-center"
            >
              <span class="i-lucide-user size-4 text-n-slate-11" />
              {{ t('SCHEDULED.NEW.CONTACT_LABEL') }}
            </label>
            <div v-if="selectedContact" class="mt-1 flex items-center gap-2">
              <div
                class="flex-1 border border-n-slate-3 rounded-md px-3 py-2 text-sm text-n-slate-12"
              >
                <div>
                  {{ selectedContact.name || t('SCHEDULED.NO_CONTACT_NAME') }}
                </div>
                <div class="text-xs text-n-slate-11">
                  {{ selectedContact.phone_number }}
                </div>
              </div>
              <button
                type="button"
                class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                :title="t('SCHEDULED.NEW.CLEAR_CONTACT')"
                @click="clearContact"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
            <div v-else class="mt-1 relative">
              <input
                v-model="contactQuery"
                type="text"
                autofocus
                :placeholder="t('SCHEDULED.NEW.CONTACT_PLACEHOLDER')"
                class="w-full border border-n-slate-3 rounded-md px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
              />
              <ul
                v-if="contactResults.length"
                class="absolute z-10 mt-1 w-full max-h-56 overflow-y-auto rounded-md border border-n-slate-3 bg-n-solid-1 shadow-lg"
              >
                <li
                  v-for="contact in contactResults"
                  :key="contact.id"
                  class="px-3 py-2 text-sm cursor-pointer hover:bg-n-slate-2"
                  @click="pickContact(contact)"
                >
                  <div class="text-n-slate-12">
                    {{ contact.name || t('SCHEDULED.NO_CONTACT_NAME') }}
                  </div>
                  <div class="text-xs text-n-slate-11">
                    {{ contact.phone_number || contact.email }}
                  </div>
                </li>
              </ul>
              <p
                v-else-if="contactSearchLoading"
                class="mt-1 text-xs text-n-slate-11"
              >
                {{ t('SCHEDULED.NEW.SEARCHING') }}
              </p>
            </div>
          </div>

          <!-- Via: inbox picker (visible after contact chosen) -->
          <div v-if="selectedContact">
            <label
              class="text-sm font-medium text-n-slate-12 flex gap-2 items-center"
            >
              <span class="i-lucide-mailbox size-4 text-n-slate-11" />
              {{ t('SCHEDULED.NEW.INBOX_LABEL') }}
            </label>
            <select
              v-model="selectedInboxId"
              class="mt-1 w-full border border-n-slate-3 rounded-md px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            >
              <option :value="null" disabled>
                {{ t('SCHEDULED.NEW.INBOX_PLACEHOLDER') }}
              </option>
              <option
                v-for="ci in contactInboxes"
                :key="ci.inbox.id"
                :value="ci.inbox.id"
              >
                {{ ci.inbox.name }}
              </option>
            </select>
          </div>

          <!-- Message -->
          <div>
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('SCHEDULED.NEW.MESSAGE_LABEL') }}
            </label>
            <textarea
              v-model="message"
              rows="5"
              :placeholder="t('SCHEDULED.NEW.MESSAGE_PLACEHOLDER')"
              class="mt-1 w-full border border-n-slate-3 rounded-md px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            />
          </div>

          <!-- Schedule -->
          <div>
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('SCHEDULED.NEW.SCHEDULE_LABEL') }}
            </label>
            <div
              class="mt-1 flex flex-col gap-2 border border-n-slate-3 rounded-md bg-n-alpha-2 p-2"
            >
              <button
                v-for="shortcut in scheduleShortcuts"
                :key="shortcut.id"
                type="button"
                class="!p-0 w-full flex items-center justify-between px-3 py-2 text-sm rounded-md hover:bg-n-solid-1 text-n-slate-12"
                @click="applyShortcut(shortcut)"
              >
                <span>{{ shortcut.label }}</span>
                <span class="text-xs text-n-slate-11">{{
                  shortcut.display
                }}</span>
              </button>
              <div
                class="border-t border-n-slate-3 pt-2 flex items-center gap-2"
              >
                <span class="i-lucide-keyboard size-4 text-n-slate-11" />
                <input
                  v-model="scheduledAt"
                  type="datetime-local"
                  class="flex-1 bg-transparent text-sm text-n-slate-12 focus:outline-none"
                />
              </div>
            </div>
          </div>

          <!-- Hold on reply -->
          <label
            class="flex items-start gap-3 rounded-md border border-n-slate-3 bg-n-alpha-2 px-3 py-2"
          >
            <input
              v-model="holdOnReply"
              type="checkbox"
              class="mt-0.5 accent-woot-500"
            />
            <div>
              <div class="text-sm font-medium text-n-slate-12">
                {{ t('SCHEDULED.NEW.HOLD_ON_REPLY') }}
              </div>
              <div class="text-xs text-n-slate-11 mt-0.5">
                {{ t('SCHEDULED.NEW.HOLD_ON_REPLY_HINT') }}
              </div>
            </div>
          </label>
        </div>

        <footer
          class="border-t border-n-slate-4 px-6 py-3 flex justify-end gap-2"
        >
          <button
            type="button"
            class="px-4 py-2 rounded-md text-sm text-n-slate-12 hover:bg-n-alpha-2"
            @click="close"
          >
            {{ t('SCHEDULED.NEW.CANCEL') }}
          </button>
          <button
            type="button"
            class="px-4 py-2 rounded-md text-sm font-medium bg-woot-500 text-white disabled:opacity-40"
            :disabled="!canSubmit"
            @click="submit"
          >
            {{
              isSaving ? t('SCHEDULED.NEW.SAVING') : t('SCHEDULED.NEW.SUBMIT')
            }}
          </button>
        </footer>
      </div>
    </div>
  </teleport>
</template>
