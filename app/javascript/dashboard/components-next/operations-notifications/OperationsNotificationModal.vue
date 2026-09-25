<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TermsSignatureBody from './TermsSignatureBody.vue';

// Modal that blocks the user when there is at least one pending
// Operations Notification. Shows ONE notification at a time; clicking
// "Entendi" acknowledges it (backend records ip + user_agent) and
// advances to the next pending one. When the queue is empty the modal
// closes and the rest of the app boot continues — including the
// Release Notes modal that watches a separate signal.
//
// Poll cadence: every 30s (POLL_INTERVAL_MS). This is the "MVP B"
// option from the original spec. PR 3 will switch this to ActionCable
// push for the `immediate` trigger.

const POLL_INTERVAL_MS = 30_000;

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const pollHandle = ref(null);

const pending = computed(
  () => store.getters['operationsNotifications/getPending']
);
const uiFlags = computed(
  () => store.getters['operationsNotifications/getUIFlags']
);

// We always show the OLDEST-published pending notification first so the
// queue drains in arrival order. Backend already orders by severity DESC
// then created_at DESC, so flipping the array gives oldest-first.
const currentNotification = computed(() => {
  if (!pending.value.length) return null;
  return [...pending.value].reverse()[0];
});

const isEmergency = computed(
  () => currentNotification.value?.severity === 'emergency'
);

// A campaign notification renders scroll + checkbox + Sign in place of the
// generic body + "Entendi" button — the ack is a legal signature there,
// not a "read receipt".
const isTermsSignature = computed(
  () => currentNotification.value?.subject_type === 'TermsAcceptanceRequest'
);

watch(currentNotification, next => {
  if (next) dialogRef.value?.open();
  else dialogRef.value?.close();
});

// The Quill editor wraps the title into `<p>...</p>` — a nested `<p>`
// inside an `<h3>` is invalid HTML and the browser resets the heading's
// font-size / font-weight, so the title used to look like body copy.
// Strip a single leading/trailing `<p>` (Quill only ever produces one
// on a plain title) so the heading styles win.
const titleHtml = computed(() => {
  const raw = currentNotification.value?.title || '';
  return raw
    .replace(/^\s*<p[^>]*>/i, '')
    .replace(/<\/p>\s*$/i, '')
    .trim();
});

const acknowledgeCurrent = async () => {
  const id = currentNotification.value?.id;
  if (!id) return;
  await store.dispatch('operationsNotifications/acknowledge', id);
  // After acknowledge, the store removes the item from `pending`;
  // the `watch(currentNotification)` handler then either opens the
  // next one or closes the dialog.
};

const startPolling = () => {
  if (pollHandle.value) return;
  pollHandle.value = window.setInterval(() => {
    store.dispatch('operationsNotifications/fetchPending');
  }, POLL_INTERVAL_MS);
};

const stopPolling = () => {
  if (pollHandle.value) {
    window.clearInterval(pollHandle.value);
    pollHandle.value = null;
  }
};

onMounted(() => {
  store.dispatch('operationsNotifications/fetchPending');
  startPolling();
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="xl"
    position="center"
    :show-cancel-button="false"
    :show-confirm-button="false"
    :dismissable="false"
  >
    <TermsSignatureBody
      v-if="currentNotification && isTermsSignature"
      :notification="currentNotification"
    />
    <div v-else-if="currentNotification" class="flex flex-col gap-4">
      <div
        v-if="isEmergency"
        class="px-3 py-2 text-sm font-medium border rounded-md bg-n-ruby-3 border-n-ruby-7 text-n-ruby-11"
      >
        {{ t('OPERATIONS_NOTIFICATIONS.EMERGENCY_BADGE') }}
      </div>
      <div
        v-else
        class="px-3 py-2 text-sm font-medium border rounded-md bg-n-blue-3 border-n-blue-7 text-n-blue-11"
      >
        {{ t('OPERATIONS_NOTIFICATIONS.INFO_BADGE') }}
      </div>
      <!-- Title and body arrive as HTML from the super-admin editor
           (already sanitized on the server). Arbitrary-variant Tailwind
           utilities constrain everything inside so a long URL breaks
           instead of scrolling the modal sideways, embedded media fit
           the width, and lists / headings render with sensible margins.
           `[overflow-wrap:anywhere]` is what does the long-URL work;
           `break-words` alone lets the browser prefer whole-word breaks
           and long slugs still overflow. -->
      <h3
        class="text-lg font-semibold text-n-slate-12 break-words [overflow-wrap:anywhere] [&_a]:underline [&_a]:text-n-blue-11"
        v-html="titleHtml"
      />
      <div
        class="text-sm text-n-slate-12 max-w-full break-words [overflow-wrap:anywhere] [&_a]:underline [&_a]:text-n-blue-11 [&_img]:max-w-full [&_img]:h-auto [&_img]:rounded-md [&_video]:max-w-full [&_video]:h-auto [&_video]:rounded-md [&_iframe]:max-w-full [&_iframe]:aspect-video [&_iframe]:w-full [&_iframe]:rounded-md [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_h1]:text-lg [&_h1]:font-semibold [&_h2]:text-base [&_h2]:font-semibold [&_h3]:text-sm [&_h3]:font-semibold [&_blockquote]:border-l-4 [&_blockquote]:border-n-slate-4 [&_blockquote]:pl-3 [&_blockquote]:italic [&_pre]:bg-n-slate-2 [&_pre]:rounded-md [&_pre]:p-3 [&_pre]:overflow-x-auto [&_code]:font-mono [&_p]:mb-2 [&_p:last-child]:mb-0"
        v-html="currentNotification.body"
      />
      <p v-if="pending.length > 1" class="text-xs text-n-slate-10">
        {{
          t('OPERATIONS_NOTIFICATIONS.MORE_PENDING', {
            count: pending.length - 1,
          })
        }}
      </p>
    </div>
    <template v-if="!isTermsSignature" #footer>
      <div class="flex items-center justify-end w-full">
        <Button
          color="blue"
          :label="t('OPERATIONS_NOTIFICATIONS.ACKNOWLEDGE')"
          type="button"
          :is-loading="uiFlags.isAcknowledging"
          @click="acknowledgeCurrent"
        />
      </div>
    </template>
  </Dialog>
</template>
