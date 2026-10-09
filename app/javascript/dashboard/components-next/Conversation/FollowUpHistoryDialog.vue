<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ConversationAPI from 'dashboard/api/conversations';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { delayLabel } from './followUpFormatters';

// Every FUP the conversation got, newest sequence first: number, waiting
// time, when it ran, whether the message went out and what came of it.
const props = defineProps({
  conversationId: { type: Number, required: true },
});

const { t } = useI18n();
const dialogRef = ref(null);
const followUps = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

const runs = computed(() => {
  const byRun = new Map();
  followUps.value.forEach(followUp => {
    if (!byRun.has(followUp.run_id)) byRun.set(followUp.run_id, []);
    byRun.get(followUp.run_id).push(followUp);
  });
  return [...byRun.entries()]
    .map(([id, items]) => ({
      id,
      items: items.sort((a, b) => a.step - b.step),
    }))
    .sort((a, b) => b.items[0].created_at - a.items[0].created_at);
});

const dateTime = seconds =>
  seconds
    ? new Date(seconds * 1000).toLocaleString(undefined, {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

const DELIVERY_CLASSES = {
  sent: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
  pending: 'bg-n-amber-3 text-n-amber-11',
};
const OUTCOME_CLASSES = {
  waiting: 'bg-n-blue-3 text-n-blue-11',
  reengaged: 'bg-n-teal-3 text-n-teal-11',
  closed: 'bg-n-alpha-2 text-n-slate-11',
  no_response: 'bg-n-amber-3 text-n-amber-11',
};

const deliveryLabels = computed(() => ({
  sent: t('CONVERSATION.FOLLOW_UP.DELIVERY.SENT'),
  failed: t('CONVERSATION.FOLLOW_UP.DELIVERY.FAILED'),
  pending: t('CONVERSATION.FOLLOW_UP.DELIVERY.PENDING'),
}));
const outcomeLabels = computed(() => ({
  waiting: t('CONVERSATION.FOLLOW_UP.OUTCOME.WAITING'),
  reengaged: t('CONVERSATION.FOLLOW_UP.OUTCOME.REENGAGED'),
  closed: t('CONVERSATION.FOLLOW_UP.OUTCOME.CLOSED'),
  no_response: t('CONVERSATION.FOLLOW_UP.OUTCOME.NO_RESPONSE'),
}));

const open = async () => {
  isLoading.value = true;
  hasError.value = false;
  dialogRef.value?.open();
  try {
    const { data } = await ConversationAPI.getFollowUps(props.conversationId);
    followUps.value = data.payload || [];
  } catch (error) {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    :title="t('CONVERSATION.FOLLOW_UP.HISTORY.TITLE')"
    :description="t('CONVERSATION.FOLLOW_UP.HISTORY.DESCRIPTION')"
    :show-confirm-button="false"
    :cancel-button-label="t('CONVERSATION.FOLLOW_UP.HISTORY.CLOSE')"
  >
    <p v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('CONVERSATION.FOLLOW_UP.HISTORY.LOADING') }}
    </p>
    <p v-else-if="hasError" class="text-sm text-n-ruby-11">
      {{ t('CONVERSATION.FOLLOW_UP.HISTORY.ERROR') }}
    </p>
    <p v-else-if="!runs.length" class="text-sm text-n-slate-11">
      {{ t('CONVERSATION.FOLLOW_UP.HISTORY.EMPTY') }}
    </p>
    <div v-else class="flex flex-col gap-5">
      <section v-for="run in runs" :key="run.id">
        <h4 class="mb-2 text-xs font-medium text-n-slate-11">
          {{
            t('CONVERSATION.FOLLOW_UP.HISTORY.RUN', {
              date: dateTime(run.items[0].created_at),
            })
          }}
        </h4>
        <table class="w-full text-sm">
          <thead class="text-xs text-n-slate-11">
            <tr>
              <th class="py-1.5 pe-3 font-medium text-start">
                {{ t('CONVERSATION.FOLLOW_UP.HISTORY.STEP') }}
              </th>
              <th class="py-1.5 pe-3 font-medium text-start">
                {{ t('CONVERSATION.FOLLOW_UP.HISTORY.WAIT') }}
              </th>
              <th class="py-1.5 pe-3 font-medium text-start">
                {{ t('CONVERSATION.FOLLOW_UP.HISTORY.RAN_AT') }}
              </th>
              <th class="py-1.5 pe-3 font-medium text-start">
                {{ t('CONVERSATION.FOLLOW_UP.HISTORY.DELIVERY') }}
              </th>
              <th class="py-1.5 font-medium text-start">
                {{ t('CONVERSATION.FOLLOW_UP.HISTORY.OUTCOME') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="followUp in run.items"
              :key="followUp.id"
              class="text-n-slate-12 align-top"
            >
              <td class="py-2 pe-3 whitespace-nowrap">
                {{
                  t('CONVERSATION.FOLLOW_UP.HISTORY.STEP_LABEL', {
                    step: followUp.step,
                  })
                }}
              </td>
              <td class="py-2 pe-3 whitespace-nowrap">
                {{ delayLabel(followUp.delay_minutes) }}
              </td>
              <td class="py-2 pe-3 whitespace-nowrap text-n-slate-11">
                {{ dateTime(followUp.processed_at || followUp.created_at) }}
              </td>
              <td class="py-2 pe-3">
                <span
                  class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="DELIVERY_CLASSES[followUp.delivery_status]"
                >
                  {{ deliveryLabels[followUp.delivery_status] }}
                </span>
                <p
                  v-if="followUp.error_message"
                  class="mt-1 mb-0 text-xs text-n-ruby-11"
                >
                  {{ followUp.error_message }}
                </p>
              </td>
              <td class="py-2">
                <span
                  class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="OUTCOME_CLASSES[followUp.outcome]"
                >
                  {{ outcomeLabels[followUp.outcome] }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
  </Dialog>
</template>
