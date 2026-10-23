<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import AudiencesAPI from 'dashboard/api/audiences';
import ContactAPI from 'dashboard/api/contacts';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// Adds contacts to a fixed audience by hand: search, tick, add.
const props = defineProps({
  audienceId: { type: [Number, String], required: true },
});

const emit = defineEmits(['added']);

const { t } = useI18n();
const dialogRef = ref(null);
const query = ref('');
const results = ref([]);
const picked = ref({});
const isSaving = ref(false);

const pickedIds = computed(() =>
  Object.keys(picked.value).filter(id => picked.value[id])
);

const search = useDebounceFn(async () => {
  if (!query.value.trim()) {
    results.value = [];
    return;
  }
  const { data } = await ContactAPI.search(query.value);
  results.value = data.payload;
}, 300);

watch(query, search);

const open = () => {
  query.value = '';
  results.value = [];
  picked.value = {};
  dialogRef.value?.open();
};

const add = async () => {
  isSaving.value = true;
  try {
    await AudiencesAPI.addContacts(props.audienceId, pickedIds.value);
    useAlert(t('AUDIENCES.ADD_DIALOG.SUCCESS'));
    dialogRef.value?.close();
    emit('added');
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AUDIENCES.ADD_DIALOG.TITLE')"
    :description="t('AUDIENCES.ADD_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('AUDIENCES.ADD_DIALOG.CONFIRM')"
    :disable-confirm-button="!pickedIds.length"
    :is-loading="isSaving"
    overflow-y-auto
    @confirm="add"
  >
    <div class="flex flex-col gap-3">
      <Input v-model="query" :placeholder="t('AUDIENCES.ADD_DIALOG.SEARCH')" />
      <p v-if="query && !results.length" class="mb-0 text-sm text-n-slate-11">
        {{ t('AUDIENCES.ADD_DIALOG.EMPTY') }}
      </p>
      <label
        v-for="contact in results"
        :key="contact.id"
        class="flex items-center gap-3 text-sm text-n-slate-12"
      >
        <Checkbox v-model="picked[contact.id]" />
        <span class="flex-grow">{{ contact.name }}</span>
        <span class="text-xs text-n-slate-11">
          {{ contact.phone_number || contact.email }}
        </span>
      </label>
    </div>
  </Dialog>
</template>
