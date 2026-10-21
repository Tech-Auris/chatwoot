<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import format from 'date-fns/format';

import ConversationAPI from 'dashboard/api/inbox/conversation';
import MessageAPI from 'dashboard/api/inbox/message';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import MessageList from 'next/message/MessageList.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// The contact's earlier conversations in the same inbox, opened one at a time
// on top of the current one: a banner offers the conversation right before,
// opening it shows it whole (read-only) and offers the one before it, and so
// on until the first. The oldest open one sits on top, the current below.
const props = defineProps({
  conversationId: { type: Number, required: true },
  contactName: { type: String, default: '' },
  currentUserId: { type: Number, required: true },
  isAnEmailChannel: { type: Boolean, default: false },
});

const { t } = useI18n();
const route = useRoute();
const rootRef = ref(null);

// The conversation the banner offers next, and the ones already open (the
// one right before the current conversation first).
const next = ref(null);
const chain = ref([]);

const MESSAGES_PER_REQUEST = 100;

const fetchPrevious = async conversationId => {
  const { data } = await ConversationAPI.getPrevious(conversationId);
  return data.payload;
};

const fetchAllMessages = async conversationId => {
  const messages = [];
  let after = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    // eslint-disable-next-line no-await-in-loop
    const { data } = await MessageAPI.getMessagesAfter({
      conversationId,
      after,
    });
    const page = data.payload || [];
    messages.push(...page);
    if (page.length < MESSAGES_PER_REQUEST) return messages;
    after = page[page.length - 1].id;
  }
};

// Content added above what the agent is reading must not push it down.
const keepScrollPosition = async change => {
  const panel = rootRef.value?.closest('.conversation-panel');
  const heightBefore = panel?.scrollHeight ?? 0;
  const topBefore = panel?.scrollTop ?? 0;
  change();
  await nextTick();
  if (panel) panel.scrollTop = topBefore + (panel.scrollHeight - heightBefore);
};

const openNext = async () => {
  const conversation = next.value;
  const entry = { conversation, messages: [], loading: true };
  await keepScrollPosition(() => {
    next.value = null;
    chain.value = [...chain.value, entry];
  });
  const [messages, before] = await Promise.all([
    fetchAllMessages(conversation.id),
    conversation.has_previous ? fetchPrevious(conversation.id) : null,
  ]);
  await keepScrollPosition(() => {
    chain.value = chain.value.map(item =>
      item.conversation.id === conversation.id
        ? { ...item, messages, loading: false }
        : item
    );
    next.value = before;
  });
};

// Closing a conversation also closes the older ones opened above it, and the
// banner offers it again.
const close = index => {
  const closed = chain.value[index];
  chain.value = chain.value.slice(0, index);
  next.value = closed.conversation;
};

const blocks = computed(() =>
  chain.value
    .map((entry, index) => ({
      ...entry,
      index,
      followingId:
        index === 0
          ? props.conversationId
          : chain.value[index - 1].conversation.id,
    }))
    .reverse()
);

const showHistoryStart = computed(() => chain.value.length > 0 && !next.value);

const formatDate = timestamp =>
  format(new Date(timestamp * 1000), 'dd/MM/yyyy');

const statusLabel = status =>
  ({
    open: t('CONVERSATION.PREVIOUS_CONVERSATION.STATUS.OPEN'),
    resolved: t('CONVERSATION.PREVIOUS_CONVERSATION.STATUS.RESOLVED'),
    pending: t('CONVERSATION.PREVIOUS_CONVERSATION.STATUS.PENDING'),
    snoozed: t('CONVERSATION.PREVIOUS_CONVERSATION.STATUS.SNOOZED'),
  })[status];

const details = conversation =>
  t('CONVERSATION.PREVIOUS_CONVERSATION.DETAILS', {
    date: formatDate(conversation.created_at),
    inbox: conversation.inbox_name,
    status: statusLabel(conversation.status),
  });

const conversationPath = id =>
  frontendURL(conversationUrl({ accountId: route.params.accountId, id }));

onMounted(async () => {
  next.value = await fetchPrevious(props.conversationId);
});
</script>

<template>
  <li ref="rootRef" class="flex flex-col gap-3 py-3 list-none">
    <div
      v-if="showHistoryStart"
      class="self-center flex items-center gap-1.5 px-3 py-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
    >
      <i class="i-lucide-arrow-up-to-line size-3.5" aria-hidden="true" />
      {{
        t('CONVERSATION.PREVIOUS_CONVERSATION.HISTORY_START', {
          name: contactName,
        })
      }}
    </div>

    <button
      v-if="next"
      type="button"
      class="flex items-center w-full gap-2.5 px-3.5 py-2.5 text-left border border-dashed rounded-lg border-n-amber-7 bg-n-amber-2 text-n-amber-11 hover:bg-n-amber-3"
      @click="openNext"
    >
      <i class="i-lucide-history size-4 shrink-0" aria-hidden="true" />
      <span class="flex flex-col flex-grow min-w-0 gap-0.5">
        <span class="text-sm font-semibold">
          {{ t('CONVERSATION.PREVIOUS_CONVERSATION.OPEN', { id: next.id }) }}
        </span>
        <span class="text-xs">
          {{
            t(
              'CONVERSATION.PREVIOUS_CONVERSATION.DETAILS_WITH_MESSAGES',
              next.messages_count,
              { details: details(next), count: next.messages_count }
            )
          }}
        </span>
      </span>
      <i class="i-lucide-chevron-down size-4 shrink-0" aria-hidden="true" />
    </button>

    <section
      v-for="block in blocks"
      :key="block.conversation.id"
      :aria-label="
        t('CONVERSATION.PREVIOUS_CONVERSATION.TITLE', {
          id: block.conversation.id,
        })
      "
      class="flex flex-col overflow-hidden border rounded-xl border-n-amber-7 bg-n-amber-2"
    >
      <header
        class="flex items-center gap-2.5 px-3.5 py-2.5 border-b border-n-amber-6 bg-n-amber-3 text-n-amber-11"
      >
        <i class="i-lucide-history size-4 shrink-0" aria-hidden="true" />
        <span class="flex flex-col flex-grow min-w-0 gap-0.5">
          <span class="text-sm font-semibold">
            {{
              t('CONVERSATION.PREVIOUS_CONVERSATION.TITLE', {
                id: block.conversation.id,
              })
            }}
          </span>
          <span class="text-xs">{{ details(block.conversation) }}</span>
        </span>
        <router-link
          :to="conversationPath(block.conversation.id)"
          class="text-xs font-medium underline text-n-amber-11 hover:text-n-amber-12"
        >
          {{
            t('CONVERSATION.PREVIOUS_CONVERSATION.OPEN_LINK', {
              id: block.conversation.id,
            })
          }}
        </router-link>
        <button
          type="button"
          class="flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium border rounded-lg border-n-amber-7 bg-n-solid-1 text-n-amber-11 hover:bg-n-amber-2"
          @click="close(block.index)"
        >
          {{ t('CONVERSATION.PREVIOUS_CONVERSATION.CLOSE') }}
          <i class="i-lucide-chevron-up size-3.5" aria-hidden="true" />
        </button>
      </header>

      <div v-if="block.loading" class="flex justify-center py-6">
        <Spinner class="text-n-amber-11" />
      </div>
      <MessageList
        v-else
        read-only
        class="py-3"
        :current-user-id="currentUserId"
        :is-an-email-channel="isAnEmailChannel"
        :messages="block.messages"
      />

      <div
        class="px-3.5 py-2 text-xs font-medium text-center border-t border-dashed border-n-amber-7 text-n-amber-11"
      >
        {{
          t('CONVERSATION.PREVIOUS_CONVERSATION.END_DIVIDER', {
            id: block.conversation.id,
            nextId: block.followingId,
          })
        }}
      </div>
    </section>
  </li>
</template>
