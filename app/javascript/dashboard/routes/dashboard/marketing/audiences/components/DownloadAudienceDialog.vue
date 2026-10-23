<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import AudiencesAPI from 'dashboard/api/audiences';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// "Baixar lista": pick the columns and get the CSV right away. The download
// is recorded under the audience's "Ações".
const props = defineProps({
  audience: { type: Object, required: true },
});

const emit = defineEmits(['downloaded']);

const { t } = useI18n();
const dialogRef = ref(null);
const isDownloading = ref(false);

const COLUMN_KEYS = [
  'name',
  'phone_number',
  'email',
  'funnel_stage',
  'loss_reason',
  'labels',
  'inbox',
  'origem',
  'origin_date',
  'assignee',
  'conversation_id',
];

const columnLabels = computed(() => ({
  name: t('AUDIENCES.DOWNLOAD.COLUMN.NAME'),
  phone_number: t('AUDIENCES.DOWNLOAD.COLUMN.PHONE_NUMBER'),
  email: t('AUDIENCES.DOWNLOAD.COLUMN.EMAIL'),
  funnel_stage: t('AUDIENCES.DOWNLOAD.COLUMN.FUNNEL_STAGE'),
  loss_reason: t('AUDIENCES.DOWNLOAD.COLUMN.LOSS_REASON'),
  labels: t('AUDIENCES.DOWNLOAD.COLUMN.LABELS'),
  inbox: t('AUDIENCES.DOWNLOAD.COLUMN.INBOX'),
  origem: t('AUDIENCES.DOWNLOAD.COLUMN.ORIGEM'),
  origin_date: t('AUDIENCES.DOWNLOAD.COLUMN.ORIGIN_DATE'),
  assignee: t('AUDIENCES.DOWNLOAD.COLUMN.ASSIGNEE'),
  conversation_id: t('AUDIENCES.DOWNLOAD.COLUMN.CONVERSATION_ID'),
}));

const picked = ref(Object.fromEntries(COLUMN_KEYS.map(key => [key, true])));
const pickedColumns = computed(() =>
  COLUMN_KEYS.filter(key => picked.value[key])
);

const open = () => dialogRef.value?.open();

const download = async () => {
  isDownloading.value = true;
  try {
    const { data } = await AudiencesAPI.exportList(
      props.audience.id,
      pickedColumns.value
    );
    downloadCsvFile(`${props.audience.name}.csv`, data);
    useAlert(t('AUDIENCES.DOWNLOAD.SUCCESS'));
    dialogRef.value?.close();
    emit('downloaded');
  } catch {
    useAlert(t('AUDIENCES.DOWNLOAD.ERROR'));
  } finally {
    isDownloading.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AUDIENCES.DOWNLOAD.TITLE', { name: audience.name })"
    :description="t('AUDIENCES.DOWNLOAD.DESCRIPTION')"
    :confirm-button-label="t('AUDIENCES.DOWNLOAD.CONFIRM')"
    :disable-confirm-button="!pickedColumns.length || audience.over_limit"
    :is-loading="isDownloading"
    overflow-y-auto
    @confirm="download"
  >
    <div class="flex flex-col gap-3">
      <p
        v-if="audience.over_limit"
        class="px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        {{ t('AUDIENCES.SHOW.OVER_LIMIT') }}
      </p>
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('AUDIENCES.DOWNLOAD.COLUMNS') }}
      </p>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label
          v-for="key in COLUMN_KEYS"
          :key="key"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <Checkbox v-model="picked[key]" />
          {{ columnLabels[key] }}
        </label>
      </div>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('AUDIENCES.DOWNLOAD.NOTE') }}
      </p>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('AUDIENCES.DOWNLOAD.FORMAT_NOTE') }}
      </p>
    </div>
  </Dialog>
</template>
