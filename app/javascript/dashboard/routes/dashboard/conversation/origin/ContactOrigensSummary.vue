<script setup>
// Multi-touch view for a contact's origem history. Sits under the OrigemSelector
// dropdown so the operator can see, at a glance, that "this contact came from
// Facebook on one conversation and from Google on another". Only renders when
// the contact has past conversations with an origem set (otherwise it's noise).
//
// Reuses the `contactConversations` store the "Previous conversations" panel
// already populates — no duplicate request when both are visible.
import { computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const conversationsForContact = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);

onMounted(() => {
  if (props.contactId) {
    store.dispatch('contactConversations/get', props.contactId);
  }
});
watch(
  () => props.contactId,
  next => {
    if (next) store.dispatch('contactConversations/get', next);
  }
);

// Group by origem so a contact who reengaged three times from Facebook shows
// "Facebook (3)" instead of three separate lines cluttering the sidebar.
const origemBreakdown = computed(() => {
  const list = conversationsForContact.value(props.contactId) || [];
  const counts = new Map();
  list.forEach(conv => {
    const origem = conv?.origem;
    if (!origem) return;
    counts.set(origem, (counts.get(origem) || 0) + 1);
  });
  return Array.from(counts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count);
});

const hasMultipleOrigens = computed(() => origemBreakdown.value.length > 1);
</script>

<template>
  <div>
    <template v-if="hasMultipleOrigens">
      <span class="text-[11px] normal-case text-n-slate-11">
        {{ t('CONVERSATION_ORIGIN.HISTORY_TITLE') }}
      </span>
      <div class="flex flex-wrap gap-1.5 mt-1">
        <span
          v-for="entry in origemBreakdown"
          :key="entry.name"
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-n-alpha-2 text-n-slate-12"
        >
          {{ entry.name }}
          <span class="text-n-slate-11">{{
            t('CONVERSATION_ORIGIN.HISTORY_COUNT', { count: entry.count })
          }}</span>
        </span>
      </div>
    </template>
  </div>
</template>
