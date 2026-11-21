<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import PipelinesAPI from 'dashboard/api/pipelines';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// "+ Adicionar contato" on the board of a clinic pipeline: finds a contact by
// name or phone and puts it on the first stage.
const props = defineProps({
  pipeline: { type: Object, default: null },
});

const emit = defineEmits(['added']);

const { t } = useI18n();

const dialogRef = ref(null);
const query = ref('');
const results = ref([]);
const isSearching = ref(false);
const addingContactId = ref(null);

const search = debounce(async () => {
  if (!query.value.trim()) {
    results.value = [];
    return;
  }
  isSearching.value = true;
  try {
    const { data } = await ContactAPI.search(
      encodeURIComponent(query.value.trim())
    );
    results.value = data?.payload || [];
  } finally {
    isSearching.value = false;
  }
}, 300);

const add = async contact => {
  addingContactId.value = contact.id;
  try {
    await PipelinesAPI.addContact(props.pipeline.id, contact.id);
    useAlert(t('PIPELINES.ADD_TO.ADDED', { pipeline: props.pipeline.name }));
    dialogRef.value?.close();
    emit('added');
  } catch (error) {
    useAlert(error?.response?.data?.message || t('PIPELINES.ADD_TO.ERROR'));
  } finally {
    addingContactId.value = null;
  }
};

const open = () => {
  query.value = '';
  results.value = [];
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="t('PIPELINES.ADD_CONTACT.TITLE', { pipeline: pipeline?.name })"
    :show-confirm-button="false"
  >
    <div class="flex flex-col gap-2">
      <input
        v-model="query"
        type="search"
        :placeholder="t('PIPELINES.ADD_CONTACT.PLACEHOLDER')"
        class="reset-base w-full h-9 px-3 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
        @input="search"
      />
      <div v-if="isSearching" class="flex justify-center py-3">
        <Spinner />
      </div>
      <div v-else class="flex flex-col max-h-72 overflow-y-auto">
        <button
          v-for="contact in results"
          :key="contact.id"
          type="button"
          class="flex items-center gap-2 px-2 py-2 rounded-lg text-start hover:bg-n-alpha-1 disabled:opacity-50"
          :disabled="addingContactId === contact.id"
          @click="add(contact)"
        >
          <Avatar
            :src="contact.thumbnail"
            :name="contact.name"
            :size="24"
            rounded-full
          />
          <span class="flex-1 min-w-0 text-sm text-n-slate-12 truncate">
            {{ contact.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ contact.phone_number }}
          </span>
        </button>
        <p
          v-if="query.trim() && !results.length"
          class="px-2 py-2 mb-0 text-sm text-n-slate-11"
        >
          {{ t('PIPELINES.ADD_CONTACT.EMPTY') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
