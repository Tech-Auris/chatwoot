<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import PipelinesAPI from 'dashboard/api/pipelines';
import LossReasonAPI from 'dashboard/api/lossReason';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AddToPipelineMenu from 'dashboard/routes/dashboard/funnel/components/AddToPipelineMenu.vue';
import LossReasonDialog from 'dashboard/routes/dashboard/funnel/components/LossReasonDialog.vue';

// "Funis (N)" on the conversation header: the clinic pipelines of the
// contact, with the stage of each (changeable here) and "Adicionar a".
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const store = useStore();
const getPipeline = useMapGetter('pipelines/getPipeline');

const entries = ref([]);
const movingEntryId = ref(null);
const lossReasons = ref([]);
const pendingMove = ref(null);
const lossReasonDialogRef = ref(null);

const openCount = computed(
  () => entries.value.filter(entry => !entry.closed_at).length
);

const fetchEntries = async () => {
  try {
    const { data } = await PipelinesAPI.contactEntries(props.contactId);
    entries.value = data?.payload || [];
  } catch (error) {
    entries.value = [];
  }
};

watch(() => props.contactId, fetchEntries, { immediate: true });

const stagesOf = entry => getPipeline.value(entry.pipeline_id)?.stages || [];

const move = async (entry, stageId, lossReasonId) => {
  movingEntryId.value = entry.id;
  try {
    await PipelinesAPI.moveEntry(entry.id, { stageId, lossReasonId });
    await fetchEntries();
    store.dispatch('pipelines/get', { force: true });
  } catch (error) {
    useAlert(error?.response?.data?.message || t('PIPELINES.MOVE_ERROR'));
  } finally {
    movingEntryId.value = null;
  }
};

const onStageChange = async (entry, event) => {
  const stageId = Number(event.target.value);
  const stage = stagesOf(entry).find(item => item.id === stageId);
  if (stage?.kind === 'lost') {
    pendingMove.value = { entry, stageId };
    if (!lossReasons.value.length) {
      const { data } = await LossReasonAPI.get();
      lossReasons.value = (data?.payload || []).filter(r => r.active);
    }
    lossReasonDialogRef.value?.open();
    return;
  }
  await move(entry, stageId);
};

const onLossReasonConfirm = async lossReasonId => {
  const { entry, stageId } = pendingMove.value;
  await move(entry, stageId, lossReasonId);
  pendingMove.value = null;
  lossReasonDialogRef.value?.close();
};

const onLossReasonClose = () => {
  pendingMove.value = null;
  fetchEntries();
};

const onShow = () => {
  store.dispatch('pipelines/get');
  fetchEntries();
};
</script>

<template>
  <Popover @show="onShow">
    <Button
      :label="t('PIPELINES.HEADER.BUTTON', { count: openCount })"
      icon="i-lucide-kanban"
      slate
      faded
      sm
    />
    <template #content>
      <div class="flex flex-col gap-2 w-80 p-3">
        <p class="mb-0 text-xs font-medium text-n-slate-11">
          {{ t('PIPELINES.HEADER.TITLE') }}
        </p>
        <div
          v-for="entry in entries"
          :key="entry.id"
          class="flex items-center gap-2"
        >
          <span class="flex-1 min-w-0 text-sm text-n-slate-12 truncate">
            {{ entry.pipeline_name }}
          </span>
          <select
            :value="entry.pipeline_stage_id"
            :disabled="movingEntryId === entry.id"
            class="h-8 max-w-40 px-2 text-sm rounded-md border border-n-weak bg-n-input-background text-n-slate-12"
            @change="event => onStageChange(entry, event)"
          >
            <option
              v-for="stage in stagesOf(entry)"
              :key="stage.id"
              :value="stage.id"
            >
              {{ stage.name }}
            </option>
          </select>
        </div>
        <p v-if="!entries.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('PIPELINES.HEADER.EMPTY') }}
        </p>
        <div class="pt-2 border-t border-n-weak">
          <AddToPipelineMenu
            :contact-id="contactId"
            :label="t('PIPELINES.ADD_TO.BUTTON')"
            size="sm"
            @changed="fetchEntries"
          />
        </div>
      </div>
    </template>
  </Popover>

  <LossReasonDialog
    ref="lossReasonDialogRef"
    :reasons="lossReasons"
    :is-submitting="!!movingEntryId"
    @confirm="onLossReasonConfirm"
    @close="onLossReasonClose"
  />
</template>
