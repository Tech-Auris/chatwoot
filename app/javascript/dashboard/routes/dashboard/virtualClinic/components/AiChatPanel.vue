<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEmitter } from 'dashboard/composables/emitter';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ChatChart from './ChatChart.vue';
import HelenaNews from './HelenaNews.vue';

const props = defineProps({
  member: { type: Object, required: true },
  // Open alerts of this teammate: shown on top and acknowledged on open.
  alertCount: { type: Number, default: 0 },
  // The manager's news for this person (notifications, new version).
  news: { type: Object, default: null },
});
const emit = defineEmits(['close', 'thinking']);

const { t, te } = useI18n();
const { formatMessage } = useMessageFormatter();

const messages = ref([]);
const alerts = ref([]);
const draft = ref('');
const notice = ref('');
const list = ref(null);

const persona = computed(() => props.member.persona);
const isThinking = computed(() =>
  messages.value.some(message => message.status === 'pending')
);
const roleLabel = computed(() =>
  t(`VIRTUAL_CLINIC.PERSONAS.${persona.value.toUpperCase()}`)
);

watch(isThinking, value => emit('thinking', value ? persona.value : ''));

const scrollToBottom = async () => {
  await nextTick();
  if (list.value) list.value.scrollTop = list.value.scrollHeight;
};

// What the teammate raised her hand for, as her latest words, until seen.
const loadAlerts = async () => {
  if (!props.alertCount) return;
  const { data } = await VirtualClinicAPI.getAlerts();
  alerts.value = data.alerts.filter(alert => alert.persona === persona.value);
  scrollToBottom();
  await VirtualClinicAPI.acknowledgeAlerts(persona.value);
};

const load = async () => {
  notice.value = '';
  const { data } = await VirtualClinicAPI.getThread(persona.value);
  messages.value = data.messages;
  scrollToBottom();
  loadAlerts();
};
watch(persona, load, { immediate: true });

const toolLabel = name => {
  const key = `VIRTUAL_CLINIC.TOOLS.${name.toUpperCase()}`;
  return te(key) ? t(key) : name;
};
const toolsUsed = message =>
  [
    ...new Set((message.tool_calls || []).map(call => toolLabel(call.name))),
  ].join(' · ');

const send = async content => {
  const text = content.trim();
  if (!text || isThinking.value) return;
  notice.value = '';
  try {
    const { data } = await VirtualClinicAPI.sendMessage(persona.value, text);
    draft.value = '';
    messages.value.push(...data.messages);
    scrollToBottom();
  } catch (error) {
    notice.value =
      error.response?.status === 429
        ? t('VIRTUAL_CLINIC.CHAT.DAILY_LIMIT')
        : t('VIRTUAL_CLINIC.CHAT.SEND_ERROR');
  }
};

const retry = message => {
  const index = messages.value.indexOf(message);
  const question = messages.value
    .slice(0, index)
    .reverse()
    .find(item => item.role === 'user');
  if (question) send(question.content);
};

const reset = async () => {
  await VirtualClinicAPI.resetThread(persona.value);
  messages.value = [];
  notice.value = '';
};

const onKeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    send(draft.value);
  }
};

// While the answer is written: the text so far, and which tool is in use.
const patchPending = (id, patch) => {
  const message = messages.value.find(item => item.id === id);
  if (message?.status !== 'pending') return;
  Object.assign(message, patch);
  scrollToBottom();
};
useEmitter('virtualClinicMessageDelta', data =>
  patchPending(data.id, { content: data.content, activity: null })
);
useEmitter('virtualClinicMessageActivity', data =>
  patchPending(data.id, { content: null, activity: data.tool })
);

useEmitter('virtualClinicMessageUpdated', data => {
  const index = messages.value.findIndex(message => message.id === data.id);
  if (index === -1) return;
  messages.value.splice(index, 1, data);
  scrollToBottom();
});
</script>

<template>
  <aside
    class="flex flex-col h-full border-l w-[26rem] shrink-0 border-n-weak bg-n-solid-1"
    @keydown.esc="emit('close')"
  >
    <header class="flex items-center gap-3 px-4 py-3 border-b border-n-weak">
      <span
        class="grid text-sm font-semibold rounded-full size-9 place-items-center bg-n-teal-3 text-n-teal-11"
      >
        {{ member.name.charAt(0) }}
      </span>
      <div class="flex flex-col min-w-0">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ member.name }}
          <span class="ml-1 text-xs font-medium text-n-teal-11">
            {{ roleLabel }}
          </span>
        </span>
        <span class="text-xs truncate text-n-slate-11">
          {{ t(`VIRTUAL_CLINIC.CHAT.SUBTITLE.${persona.toUpperCase()}`) }}
        </span>
      </div>
      <Button
        :label="t('VIRTUAL_CLINIC.CHAT.NEW')"
        icon="i-lucide-rotate-ccw"
        variant="ghost"
        size="xs"
        class="ml-auto"
        @click="reset"
      />
      <Button
        icon="i-lucide-x"
        variant="ghost"
        color="slate"
        size="xs"
        @click="emit('close')"
      />
    </header>

    <div ref="list" class="flex flex-col flex-1 gap-3 p-4 overflow-y-auto">
      <template v-for="message in messages" :key="message.id">
        <p
          v-if="message.role === 'user'"
          class="self-end max-w-[80%] px-3 py-2 text-sm text-white rounded-2xl rounded-br-sm bg-n-brand whitespace-pre-wrap"
        >
          {{ message.content }}
        </p>
        <div
          v-else-if="message.status === 'pending' && message.content"
          class="self-start max-w-[92%] px-3 py-2 text-sm rounded-2xl rounded-bl-sm bg-n-alpha-2 text-n-slate-12"
        >
          <div
            v-dompurify-html="formatMessage(message.content, false, false)"
            class="leading-relaxed [&_ol]:list-decimal [&_ol]:pl-5 [&_ul]:list-disc [&_ul]:pl-5"
          />
          <span
            class="inline-block w-1.5 h-3.5 align-middle animate-pulse bg-n-slate-10"
          />
        </div>
        <div
          v-else-if="message.status === 'pending'"
          class="self-start px-3 py-2 text-sm rounded-2xl rounded-bl-sm bg-n-alpha-2 text-n-slate-11"
        >
          {{
            message.activity
              ? t('VIRTUAL_CLINIC.CHAT.ACTIVITY', {
                  name: member.name,
                  tool: toolLabel(message.activity),
                })
              : t('VIRTUAL_CLINIC.CHAT.THINKING', { name: member.name })
          }}
        </div>
        <div
          v-else-if="message.status === 'failed'"
          class="self-start max-w-[92%] px-3 py-2 text-sm rounded-2xl rounded-bl-sm bg-n-ruby-2 text-n-ruby-11"
        >
          <p>{{ message.content }}</p>
          <button
            type="button"
            class="mt-1 text-xs font-medium underline"
            @click="retry(message)"
          >
            {{ t('VIRTUAL_CLINIC.CHAT.RETRY') }}
          </button>
        </div>
        <div
          v-else
          class="self-start max-w-[92%] px-3 py-2 text-sm rounded-2xl rounded-bl-sm bg-n-alpha-2 text-n-slate-12"
        >
          <div
            v-dompurify-html="
              formatMessage(message.content || '', false, false)
            "
            class="leading-relaxed [&_ol]:list-decimal [&_ol]:pl-5 [&_ul]:list-disc [&_ul]:pl-5 [&_table]:w-full [&_table]:my-2 [&_td]:px-1.5 [&_td]:py-0.5 [&_td]:border-b [&_td]:border-n-weak [&_th]:px-1.5 [&_th]:text-left"
          />
          <ChatChart
            v-for="(chart, index) in message.attachments || []"
            :key="`chart-${message.id}-${index}`"
            :chart="chart"
          />
          <p
            v-if="message.tool_calls?.length"
            class="flex items-center gap-1 mt-2 text-xs text-n-slate-10"
          >
            <Icon icon="i-lucide-database" class="size-3" />
            {{
              t('VIRTUAL_CLINIC.CHAT.CONSULTED', { tools: toolsUsed(message) })
            }}
          </p>
        </div>
      </template>
      <div
        v-for="alert in alerts"
        :key="`alert-${alert.id}`"
        class="self-start max-w-[92%] px-3 py-2 text-sm border rounded-2xl rounded-bl-sm border-n-amber-5 bg-n-amber-2 text-n-amber-12"
      >
        <p class="font-medium">
          {{ t('VIRTUAL_CLINIC.CHAT.ALERT', { message: alert.message }) }}
        </p>
        <ul
          v-if="alert.payload.patients?.length"
          class="pl-5 mt-1 list-disc text-n-slate-12"
        >
          <li
            v-for="patient in alert.payload.patients"
            :key="patient.conversation_id"
          >
            {{
              t('VIRTUAL_CLINIC.CHAT.ALERT_PATIENT', {
                name: patient.name || t('VIRTUAL_CLINIC.CHAT.NO_NAME'),
                id: patient.conversation_id,
                minutes: patient.waiting_minutes,
              })
            }}
          </li>
        </ul>
        <ul
          v-if="alert.payload.inboxes?.length"
          class="pl-5 mt-1 list-disc text-n-slate-12"
        >
          <li v-for="inbox in alert.payload.inboxes" :key="inbox.name">
            {{
              inbox.reason === 'disconnected'
                ? t('VIRTUAL_CLINIC.CHAT.ALERT_DISCONNECTED', {
                    name: inbox.name,
                  })
                : t('VIRTUAL_CLINIC.CHAT.ALERT_SILENT', {
                    name: inbox.name,
                    hours: inbox.hours,
                  })
            }}
          </li>
        </ul>
      </div>
      <HelenaNews
        v-if="news"
        class="self-start max-w-[92%]"
        :notifications="news.notifications"
        :release="news.release"
      />
    </div>

    <div class="flex flex-wrap gap-1.5 px-4 pb-2">
      <button
        v-for="suggestion in member.suggestions"
        :key="suggestion"
        type="button"
        class="px-2.5 py-1 text-xs rounded-full bg-n-blue-2 text-n-blue-11 hover:bg-n-blue-3 disabled:opacity-50"
        :disabled="isThinking"
        @click="send(suggestion)"
      >
        {{ suggestion }}
      </button>
    </div>
    <p v-if="notice" class="px-4 pb-2 text-xs text-n-ruby-11">{{ notice }}</p>
    <div class="flex items-end gap-2 px-4 pb-4">
      <textarea
        v-model="draft"
        rows="2"
        class="flex-1 px-3 py-2 text-sm border rounded-xl resize-none border-n-weak bg-n-solid-2 text-n-slate-12"
        :placeholder="
          t('VIRTUAL_CLINIC.CHAT.PLACEHOLDER', { name: member.name })
        "
        :disabled="isThinking"
        @keydown="onKeydown"
      />
      <Button
        icon="i-lucide-send-horizontal"
        :disabled="isThinking || !draft.trim()"
        @click="send(draft)"
      />
    </div>
  </aside>
</template>
