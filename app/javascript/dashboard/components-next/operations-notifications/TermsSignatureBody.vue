<script setup>
// The body the OperationsNotificationModal renders when the pending
// notification carries a re-signature campaign. Shows the pinned version's
// content in a scrollable panel and gates the checkbox on reaching the
// bottom — a legal-adjacent gesture that says "I read this, I did not
// just check a box".

import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  notification: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();

const scrollContainer = ref(null);
const scrolledToBottom = ref(false);
const accepted = ref(false);

const uiFlags = computed(
  () => store.getters['operationsNotifications/getUIFlags']
);

watch(
  () => props.notification?.id,
  () => {
    scrolledToBottom.value = false;
    accepted.value = false;
  }
);

// Scroll must land within a small tolerance of the bottom to count.
// Elements a few pixels shy from the end still qualify — sub-pixel rounding
// in some browsers otherwise blocks the acceptance forever.
const SCROLL_TOLERANCE_PX = 8;
const onScroll = () => {
  const el = scrollContainer.value;
  if (!el) return;
  if (el.scrollHeight - el.scrollTop - el.clientHeight <= SCROLL_TOLERANCE_PX) {
    scrolledToBottom.value = true;
  }
};

const canSign = computed(() => scrolledToBottom.value && accepted.value);

const formatDate = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';
const formatDateTime = value =>
  value ? new Date(value * 1000).toLocaleString('pt-BR') : '—';

const sign = async () => {
  if (!canSign.value) return;
  await store.dispatch('operationsNotifications/signTerms', {
    notificationId: props.notification.id,
    token: props.notification.terms_acceptance.token,
  });
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      class="px-3 py-2 text-sm font-medium border rounded-md bg-n-ruby-3 border-n-ruby-7 text-n-ruby-11"
    >
      {{ t('OPERATIONS_NOTIFICATIONS.TERMS.TITLE') }}
    </div>

    <div class="text-xs text-n-slate-10 flex flex-wrap gap-x-4">
      <span v-if="notification.terms_version?.document_date">
        {{
          t('OPERATIONS_NOTIFICATIONS.TERMS.DOCUMENT_DATE', {
            date: formatDate(notification.terms_version.document_date),
          })
        }}
      </span>
      <span v-if="notification.terms_acceptance?.deadline_at">
        {{
          t('OPERATIONS_NOTIFICATIONS.TERMS.DEADLINE', {
            date: formatDateTime(notification.terms_acceptance.deadline_at),
          })
        }}
      </span>
    </div>

    <div
      ref="scrollContainer"
      class="border rounded-md border-n-slate-6 p-4 max-h-[50vh] overflow-y-auto text-sm text-n-slate-12 prose-sm bg-n-alpha-1"
      @scroll="onScroll"
    >
      <div v-dompurify-html="notification.terms_version?.content || ''" />
    </div>

    <p v-if="!scrolledToBottom" class="text-xs text-n-slate-10">
      {{ t('OPERATIONS_NOTIFICATIONS.TERMS.SCROLL_HINT') }}
    </p>

    <label class="flex items-start gap-2 text-sm text-n-slate-12">
      <input
        v-model="accepted"
        type="checkbox"
        class="mt-1"
        :disabled="!scrolledToBottom"
      />
      <span>{{ t('OPERATIONS_NOTIFICATIONS.TERMS.ACCEPT_CHECKBOX') }}</span>
    </label>

    <div class="flex items-center justify-end pt-2">
      <Button
        color="blue"
        :label="t('OPERATIONS_NOTIFICATIONS.TERMS.SIGN')"
        type="button"
        :disabled="!canSign"
        :is-loading="uiFlags.isSigningTerms"
        @click="sign"
      />
    </div>
  </div>
</template>
