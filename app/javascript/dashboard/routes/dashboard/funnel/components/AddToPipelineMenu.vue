<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import PipelinesAPI from 'dashboard/api/pipelines';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// "Adicionar a" (as in ClickUp): checks the clinic pipelines the contact is
// in progress in. Checking puts the contact on the first stage, unchecking
// takes it out (after a confirmation). The Agendamento shows checked and
// locked: it follows the conversation, not this menu.
const props = defineProps({
  contactId: { type: Number, required: true },
  size: { type: String, default: 'xs' },
  label: { type: String, default: '' },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const store = useStore();
const pipelines = useMapGetter('pipelines/getPipelines');

const entries = ref([]);
const isLoading = ref(false);
const busyPipelineId = ref(null);
const search = ref('');
const pendingRemoval = ref(null);
const confirmDialogRef = ref(null);

const openEntryByPipeline = computed(() =>
  Object.fromEntries(
    entries.value
      .filter(entry => !entry.closed_at)
      .map(entry => [entry.pipeline_id, entry])
  )
);

const filteredPipelines = computed(() => {
  const query = search.value.trim().toLowerCase();
  if (!query) return pipelines.value;
  return pipelines.value.filter(pipeline =>
    pipeline.name.toLowerCase().includes(query)
  );
});

const fetchEntries = async () => {
  isLoading.value = true;
  try {
    const { data } = await PipelinesAPI.contactEntries(props.contactId);
    entries.value = data?.payload || [];
  } catch (error) {
    entries.value = [];
  } finally {
    isLoading.value = false;
  }
};

const onShow = () => {
  search.value = '';
  store.dispatch('pipelines/get');
  fetchEntries();
};

const add = async pipeline => {
  busyPipelineId.value = pipeline.id;
  try {
    await PipelinesAPI.addContact(pipeline.id, props.contactId);
    useAlert(t('PIPELINES.ADD_TO.ADDED', { pipeline: pipeline.name }));
    await fetchEntries();
    emit('changed', pipeline.id);
  } catch (error) {
    useAlert(error?.response?.data?.message || t('PIPELINES.ADD_TO.ERROR'));
  } finally {
    busyPipelineId.value = null;
  }
};

const toggle = pipeline => {
  const entry = openEntryByPipeline.value[pipeline.id];
  if (!entry) {
    add(pipeline);
    return;
  }
  pendingRemoval.value = { pipeline, entry };
  confirmDialogRef.value?.open();
};

const confirmRemoval = async () => {
  const { pipeline, entry } = pendingRemoval.value;
  busyPipelineId.value = pipeline.id;
  try {
    await PipelinesAPI.removeEntry(entry.id);
    useAlert(t('PIPELINES.ADD_TO.REMOVED', { pipeline: pipeline.name }));
    confirmDialogRef.value?.close();
    await fetchEntries();
    emit('changed', pipeline.id);
  } catch (error) {
    useAlert(t('PIPELINES.ADD_TO.ERROR'));
  } finally {
    busyPipelineId.value = null;
    pendingRemoval.value = null;
  }
};
</script>

<template>
  <Popover @show="onShow">
    <Button
      v-tooltip.top="label ? '' : t('PIPELINES.ADD_TO.BUTTON')"
      icon="i-lucide-plus"
      :label="label"
      slate
      ghost
      :size="size"
      :aria-label="t('PIPELINES.ADD_TO.BUTTON')"
    />
    <template #content>
      <div class="flex flex-col w-64 max-h-80 py-2">
        <p class="px-3 pb-1 mb-0 text-xs font-medium text-n-slate-11">
          {{ t('PIPELINES.ADD_TO.TITLE') }}
        </p>
        <div class="px-2 pb-1">
          <input
            v-model="search"
            type="search"
            :placeholder="t('PIPELINES.SEARCH')"
            class="reset-base w-full h-8 px-2 text-sm border-none rounded-lg bg-n-alpha-black2 text-n-slate-12 focus:outline-none"
          />
        </div>
        <div class="flex flex-col overflow-y-auto px-1">
          <div
            class="flex items-center gap-2 h-8 px-2 text-sm text-n-slate-11"
            :title="t('PIPELINES.ADD_TO.AGENDAMENTO_LOCKED')"
          >
            <span class="i-lucide-square-check size-4 flex-shrink-0" />
            <span class="flex-1 truncate">{{
              t('PIPELINES.AGENDAMENTO')
            }}</span>
            <span class="i-lucide-lock size-3.5 flex-shrink-0" />
          </div>
          <button
            v-for="pipeline in filteredPipelines"
            :key="pipeline.id"
            type="button"
            class="flex items-center gap-2 h-8 px-2 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="isLoading || busyPipelineId === pipeline.id"
            @click="toggle(pipeline)"
          >
            <span
              class="size-4 flex-shrink-0"
              :class="
                openEntryByPipeline[pipeline.id]
                  ? 'i-lucide-square-check text-n-brand'
                  : 'i-lucide-square text-n-slate-10'
              "
            />
            <span class="flex-1 truncate text-start">{{ pipeline.name }}</span>
          </button>
          <p
            v-if="!filteredPipelines.length"
            class="px-2 py-1.5 mb-0 text-xs text-n-slate-11"
          >
            {{
              pipelines.length
                ? t('PIPELINES.ADD_TO.NO_MATCH')
                : t('PIPELINES.ADD_TO.EMPTY')
            }}
          </p>
        </div>
      </div>
    </template>
  </Popover>

  <Dialog
    ref="confirmDialogRef"
    type="alert"
    width="md"
    :title="t('PIPELINES.ADD_TO.REMOVE_TITLE')"
    :description="
      t('PIPELINES.ADD_TO.REMOVE_DESCRIPTION', {
        pipeline: pendingRemoval?.pipeline.name,
      })
    "
    :confirm-button-label="t('PIPELINES.ADD_TO.REMOVE_CONFIRM')"
    :is-loading="!!busyPipelineId"
    @confirm="confirmRemoval"
    @close="pendingRemoval = null"
  />
</template>
