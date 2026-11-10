<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// "Agendamentos após follow-up" in detail: the booked conversations split by
// the last follow-up sent before the booking. Same look as the "Sem resposta"
// dialog; the rows come with the page.
const props = defineProps({
  afterFollowUp: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();
const dialogRef = ref(null);

const blocks = computed(() => {
  const rows = props.afterFollowUp.conversations || [];
  return [
    {
      key: 'first',
      title: t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.AFTER_FIRST'),
      rows: rows.filter(row => row.step === 1),
    },
    {
      key: 'second',
      title: t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.AFTER_SECOND'),
      rows: rows.filter(row => row.step === 2),
    },
    {
      key: 'third',
      title: t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.AFTER_THIRD'),
      rows: rows.filter(row => row.step >= 3),
    },
  ];
});

const title = computed(() =>
  t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.TITLE', {
    count: (props.afterFollowUp.conversations || []).length,
  })
);

const conversationUrl = row =>
  `/app/accounts/${route.params.accountId}/conversations/${row.id}`;

const formatDateTime = timestamp =>
  new Date(timestamp * 1000).toLocaleString(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const dash = value => value || t('HOME_OVERVIEW.WAITING_DIALOG.DASH');

defineExpose({ open: () => dialogRef.value?.open() });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.DESCRIPTION')"
    width="7xl"
  >
    <div class="flex flex-col gap-5">
      <section
        v-for="block in blocks"
        :key="block.key"
        class="flex flex-col gap-2"
      >
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ block.title }}
          <span class="font-normal text-n-slate-11">
            ·
            {{ t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.COUNT', block.rows.length) }}
          </span>
        </h3>
        <p v-if="!block.rows.length" class="mb-0 text-sm text-n-slate-10">
          {{ t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.EMPTY') }}
        </p>
        <div
          v-else
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
                  {{ t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.COLUMNS.BOOKED_AT') }}
                </th>
                <th class="px-3 py-2 font-medium text-left whitespace-nowrap">
                  {{ t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.COLUMNS.BOOKED_BY') }}
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
              <tr v-for="row in block.rows" :key="row.id">
                <td class="px-3 py-2 whitespace-nowrap">
                  <a
                    :href="conversationUrl(row)"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="font-mono text-n-brand hover:underline"
                  >
                    {{
                      t('HOME_OVERVIEW.WAITING_DIALOG.HASH_ID', { id: row.id })
                    }}
                  </a>
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  <div>{{ dash(row.contact_name) }}</div>
                  <div v-if="row.contact_phone" class="text-xs text-n-slate-11">
                    {{ row.contact_phone }}
                  </div>
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  {{ formatDateTime(row.booked_at) }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  {{
                    row.booked_by ||
                    t('HOME_OVERVIEW.FOLLOW_UP_DIALOG.AUTOMATION')
                  }}
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
      </section>
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
