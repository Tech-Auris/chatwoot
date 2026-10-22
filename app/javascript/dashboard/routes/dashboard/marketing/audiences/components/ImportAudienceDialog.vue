<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AudiencesAPI from 'dashboard/api/audiences';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// A spreadsheet turned into a fixed audience, read like a campaign's CSV.
const { t } = useI18n();
const router = useRouter();

const dialogRef = ref(null);
const name = ref('');
const file = ref(null);
const isImporting = ref(false);

const canImport = computed(() => name.value.trim() && file.value);

const onFileChange = event => {
  [file.value] = event.target.files;
};

const open = () => {
  name.value = '';
  file.value = null;
  dialogRef.value?.open();
};

const importFile = async () => {
  isImporting.value = true;
  try {
    const { data } = await AudiencesAPI.importFile({
      name: name.value,
      file: file.value,
    });
    const audience = data.payload;
    const skipped = audience.invalid_rows?.length;
    useAlert(
      [
        t('AUDIENCES.IMPORT_DIALOG.SUCCESS', {
          count: audience.contacts_count,
        }),
        skipped
          ? t('AUDIENCES.IMPORT_DIALOG.INVALID_ROWS', { count: skipped })
          : '',
      ]
        .filter(Boolean)
        .join(' ')
    );
    dialogRef.value?.close();
    router.push({
      name: 'marketing_audiences_show',
      params: { audienceId: audience.id },
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('AUDIENCES.IMPORT_DIALOG.ERROR')
    );
  } finally {
    isImporting.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AUDIENCES.IMPORT_DIALOG.TITLE')"
    :description="t('AUDIENCES.IMPORT_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('AUDIENCES.IMPORT_DIALOG.CONFIRM')"
    :disable-confirm-button="!canImport"
    :is-loading="isImporting"
    @confirm="importFile"
  >
    <div class="flex flex-col gap-3">
      <Input v-model="name" :label="t('AUDIENCES.IMPORT_DIALOG.NAME')" />
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('AUDIENCES.IMPORT_DIALOG.FILE') }}
        <input
          type="file"
          accept=".csv,text/csv"
          class="text-sm text-n-slate-11"
          @change="onFileChange"
        />
      </label>
    </div>
  </Dialog>
</template>
