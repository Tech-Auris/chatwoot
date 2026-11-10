<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// The leads waiting for an answer, same look as the Conversão do funil
// drill-down. The rows come with the page, so it opens instantly.
const props = defineProps({
  waiting: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();
const dialogRef = ref(null);

const title = computed(() =>
  t('HOME_OVERVIEW.WAITING_DIALOG.TITLE', { count: props.waiting.count })
);

const description = computed(() =>
  props.waiting.count > props.waiting.conversations.length
    ? t('HOME_OVERVIEW.WAITING_DIALOG.DESCRIPTION_OLDEST', {
        shown: props.waiting.conversations.length,
      })
    : t('HOME_OVERVIEW.WAITING_DIALOG.DESCRIPTION')
);

const conversationUrl = row =>
  `/app/accounts/${route.params.accountId}/conversations/${row.id}`;

const formatDateTime = timestamp =>
  new Date(timestamp * 1000).toLocaleString(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const waitedFor = timestamp => {
  const minutes = Math.floor((Date.now() / 1000 - timestamp) / 60);
  if (minutes < 60) return t('HOME_OVERVIEW.WAITING_DIALOG.MINUTES', minutes);
  return t('HOME_OVERVIEW.WAITING_DIALOG.HOURS', {
    hours: Math.floor(minutes / 60),
    minutes: minutes % 60,
  });
};

const dash = value => value || t('HOME_OVERVIEW.WAITING_DIALOG.DASH');

defineExpose({ open: () => dialogRef.value?.open() });
</script>

<template>
  <Dialog ref="dialogRef" :title="title" :description="description" width="7xl">
    <div
      class="overflow-x-auto rounded-lg outline outline-1 outline-n-container"
    >
      <table class="w-full text-sm">
        <thead class="text-xs bg-n-slate-2 text-n-slate-11">
          <tr>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.CONVERSATION') }}
            </th>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.CONTACT') }}
            </th>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.WAITING_SINCE') }}
            </th>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.WAITING_FOR') }}
            </th>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.ASSIGNEE') }}
            </th>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.INBOX') }}
            </th>
            <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
              {{ t('HOME_OVERVIEW.WAITING_DIALOG.COLUMNS.SOURCE') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak text-n-slate-12">
          <tr v-for="row in waiting.conversations" :key="row.id">
            <td class="px-3 py-2 whitespace-nowrap">
              <a
                :href="conversationUrl(row)"
                target="_blank"
                rel="noopener noreferrer"
                class="font-mono text-n-brand hover:underline"
              >
                {{ t('HOME_OVERVIEW.WAITING_DIALOG.HASH_ID', { id: row.id }) }}
              </a>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <div>{{ dash(row.contact_name) }}</div>
              <div v-if="row.contact_phone" class="text-xs text-n-slate-11">
                {{ row.contact_phone }}
              </div>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              {{ formatDateTime(row.waiting_since) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              {{ waitedFor(row.waiting_since) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              {{ dash(row.assignee_name) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              {{ dash(row.inbox_name) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              {{ dash(row.origem) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <template #footer>
      <div class="flex justify-center">
        <Button
          type="button"
          color="blue"
          class="min-w-32"
          :label="t('HOME_OVERVIEW.WAITING_DIALOG.CLOSE')"
          @click="dialogRef.close()"
        />
      </div>
    </template>
  </Dialog>
</template>
