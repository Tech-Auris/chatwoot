<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AddToPipelineMenu from './AddToPipelineMenu.vue';
import { elapsedSince, entryOriginLabel } from '../pipelineFormatters';

// Card of a clinic pipeline: one per contact. It opens the contact's most
// recent conversation, which may change over the months the contact spends
// in the pipeline.
const props = defineProps({
  entry: { type: Object, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();
const accountId = computed(() => getters.getCurrentAccountId.value);

const contact = computed(() => props.entry.contact || {});
const conversation = computed(() => props.entry.latest_conversation);
const elapsedLabel = computed(() =>
  elapsedSince(t, props.entry.stage_entered_at)
);
const originLabel = computed(() => entryOriginLabel(t, props.entry));
const isConversationOpen = computed(
  () => conversation.value && conversation.value.status !== 'resolved'
);

const goToConversation = () => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: conversation.value.id,
    },
  });
};

const goToContact = () => {
  router.push({
    name: 'contacts_edit',
    params: { accountId: accountId.value, contactId: contact.value.id },
  });
};
</script>

<template>
  <article
    class="flex flex-col gap-2 px-3 py-2.5 bg-n-surface-1 border border-n-weak rounded-lg shadow-sm cursor-grab active:cursor-grabbing hover:border-n-slate-6"
  >
    <div class="flex flex-col gap-0.5">
      <div class="flex items-center gap-2 min-w-0">
        <Avatar
          :src="contact.thumbnail"
          :name="contact.name"
          :size="24"
          rounded-full
        />
        <span
          class="text-[13px] font-medium text-n-slate-12 truncate min-w-0 flex-1"
          :title="contact.name"
        >
          {{ contact.name }}
        </span>
        <span
          v-if="conversation"
          class="px-1.5 py-0.5 text-[11px] font-medium rounded"
          :class="
            isConversationOpen
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-slate-3 text-n-slate-11'
          "
        >
          {{
            isConversationOpen
              ? t('PIPELINES.CARD.CONVERSATION_OPEN')
              : t('PIPELINES.CARD.CONVERSATION_RESOLVED')
          }}
        </span>
      </div>
      <span v-if="contact.phone_number" class="text-xs text-n-slate-11">
        {{ contact.phone_number }}
      </span>
      <span class="text-xs text-n-slate-11 truncate" :title="originLabel">
        {{ originLabel }}
      </span>
      <span
        v-if="entry.loss_reason"
        class="inline-flex items-center gap-1 text-xs text-n-ruby-11"
      >
        <span class="i-lucide-circle-x size-3" />
        {{ entry.loss_reason.name }}
      </span>
    </div>

    <footer class="flex items-center justify-between gap-2 mt-auto">
      <span
        v-if="elapsedLabel"
        v-tooltip.top="t('PIPELINES.CARD.IN_STAGE_FOR')"
        class="inline-flex items-center gap-1 text-[11px] text-n-slate-11"
      >
        <span class="i-lucide-flag size-3" />
        {{ elapsedLabel }}
      </span>
      <div class="flex items-center gap-1 ms-auto">
        <AddToPipelineMenu
          :contact-id="contact.id"
          @changed="pipelineId => emit('changed', pipelineId)"
        />
        <button
          v-if="conversation"
          type="button"
          class="inline-flex items-center justify-center size-8 rounded text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('FUNNEL.CARD.OPEN_CONVERSATION')"
          :title="t('FUNNEL.CARD.OPEN_CONVERSATION')"
          @click="goToConversation"
        >
          <span class="i-lucide-message-circle size-5" />
        </button>
        <button
          type="button"
          class="inline-flex items-center justify-center size-8 rounded text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('FUNNEL.CARD.OPEN_CONTACT')"
          :title="t('FUNNEL.CARD.OPEN_CONTACT')"
          @click="goToContact"
        >
          <span class="i-lucide-user size-5" />
        </button>
      </div>
    </footer>
  </article>
</template>
