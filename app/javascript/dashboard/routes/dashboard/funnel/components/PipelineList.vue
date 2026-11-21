<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import { elapsedSince, entryOriginLabel } from '../pipelineFormatters';

// List view of a clinic pipeline: the same table as the Agendamento's, with
// the origin instead of the inbox and the time on the stage.
const props = defineProps({
  stages: { type: Array, required: true },
  entriesByStage: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();
const accountId = computed(() => getters.getCurrentAccountId.value);

const collapsed = ref({});
const entriesFor = stage => props.entriesByStage[stage.name] || [];
const toggle = stage => {
  collapsed.value = {
    ...collapsed.value,
    [stage.id]: !collapsed.value[stage.id],
  };
};

const goToConversation = entry =>
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: entry.latest_conversation.id,
    },
  });

const goToContact = entry =>
  router.push({
    name: 'contacts_edit',
    params: { accountId: accountId.value, contactId: entry.contact.id },
  });
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto px-6 py-4">
    <div class="flex flex-col gap-3 max-w-5xl">
      <section
        v-for="stage in stages"
        :key="stage.id"
        class="rounded-lg border border-n-weak bg-n-surface-1 overflow-hidden"
      >
        <button
          type="button"
          class="flex items-center gap-2 w-full px-4 py-2.5 text-left hover:bg-n-alpha-2"
          @click="toggle(stage)"
        >
          <span
            class="i-lucide-chevron-down size-4 text-n-slate-11 transition-transform flex-shrink-0"
            :class="{ '-rotate-90': collapsed[stage.id] }"
          />
          <span
            class="inline-block size-3 rounded-full flex-shrink-0"
            :style="{ backgroundColor: stage.color }"
          />
          <span class="text-sm font-medium text-n-slate-12 truncate">
            {{ stage.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('PIPELINES.STAGE.COUNT_LABEL', stage.count || 0, {
                count: stage.count || 0,
              })
            }}
          </span>
        </button>
        <div v-if="!collapsed[stage.id]" class="border-t border-n-weak">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1">
              <tr class="text-left text-xs text-n-slate-11">
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.CONTACT') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('FUNNEL.LIST.PHONE') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('PIPELINES.LIST.ORIGIN') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('PIPELINES.LIST.IN_STAGE_FOR') }}
                </th>
                <th class="px-4 py-2 font-medium text-right">
                  {{ t('FUNNEL.LIST.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="entry in entriesFor(stage)"
                :key="entry.id"
                class="border-t border-n-weak hover:bg-n-alpha-1"
              >
                <td class="px-4 py-2 font-medium text-n-slate-12">
                  {{ entry.contact.name }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ entry.contact.phone_number }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ entryOriginLabel(t, entry) }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ elapsedSince(t, entry.stage_entered_at) }}
                </td>
                <td class="px-4 py-2">
                  <div class="flex items-center justify-end gap-1">
                    <button
                      v-if="entry.latest_conversation"
                      type="button"
                      class="inline-flex items-center justify-center size-8 rounded text-n-slate-11 hover:bg-n-alpha-2"
                      :title="t('FUNNEL.CARD.OPEN_CONVERSATION')"
                      @click="goToConversation(entry)"
                    >
                      <span class="i-lucide-message-circle size-5" />
                    </button>
                    <button
                      type="button"
                      class="inline-flex items-center justify-center size-8 rounded text-n-slate-11 hover:bg-n-alpha-2"
                      :title="t('FUNNEL.CARD.OPEN_CONTACT')"
                      @click="goToContact(entry)"
                    >
                      <span class="i-lucide-user size-5" />
                    </button>
                  </div>
                </td>
              </tr>
              <tr v-if="!entriesFor(stage).length">
                <td
                  colspan="5"
                  class="px-4 py-6 text-center text-xs text-n-slate-11"
                >
                  {{ t('PIPELINES.LIST.EMPTY') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>
