<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import PipelinesAPI from 'dashboard/api/pipelines';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// "Configurar funil" / "Novo funil". The clinic's own stages are edited in
// place (name, color, order) and saved together; Ganho and Perdido are shown
// locked at the end. Deleting a stage that has contacts asks where they go.
const emit = defineEmits(['saved', 'archived', 'deleted']);

const { t } = useI18n();

const PALETTE = [
  '#3b82f6',
  '#10b981',
  '#f59e0b',
  '#8b5cf6',
  '#ec4899',
  '#14b8a6',
];

const dialogRef = ref(null);
const deleteDialogRef = ref(null);
const pipeline = ref(null);
const name = ref('');
const stages = ref([]);
const removed = ref([]);
const isSaving = ref(false);
const deleteConfirmation = ref('');
const affectedAutomations = ref([]);

let tempId = 0;
const isNew = computed(() => !pipeline.value);
const closingStages = computed(() =>
  (pipeline.value?.stages || []).filter(stage => stage.kind !== 'open')
);
const keptExistingStages = computed(() => stages.value.filter(s => s.id));

const open = (target = null, counts = {}) => {
  pipeline.value = target;
  name.value = target?.name || '';
  stages.value = target
    ? target.stages
        .filter(stage => stage.kind === 'open')
        .map(stage => ({ ...stage, count: counts[stage.id] || 0 }))
    : [{ key: `new-${(tempId += 1)}`, name: '', color: PALETTE[0], count: 0 }];
  removed.value = [];
  dialogRef.value?.open();
};

const addStage = () => {
  stages.value.push({
    key: `new-${(tempId += 1)}`,
    name: '',
    color: PALETTE[stages.value.length % PALETTE.length],
    count: 0,
  });
};

const removeStage = stage => {
  stages.value = stages.value.filter(item => item !== stage);
  if (stage.id) removed.value.push({ ...stage, moveTo: '' });
};

const isValid = computed(
  () =>
    name.value.trim() &&
    stages.value.length > 0 &&
    stages.value.every(stage => stage.name.trim()) &&
    removed.value.every(stage => !stage.count || stage.moveTo)
);

const errorMessage = error =>
  error?.response?.data?.message || t('PIPELINES.CONFIG.ERROR');

const createPipeline = async () => {
  const { data } = await PipelinesAPI.create({
    name: name.value.trim(),
    stages: stages.value.map(({ name: stageName, color }) => ({
      name: stageName.trim(),
      color,
    })),
  });
  return data.payload;
};

const original = id => pipeline.value.stages.find(stage => stage.id === id);

const updatePipeline = async () => {
  const id = pipeline.value.id;
  if (name.value.trim() !== pipeline.value.name) {
    await PipelinesAPI.update(id, { name: name.value.trim() });
  }
  // New stages first: they need an id for the final order.
  const orderedIds = [];
  // eslint-disable-next-line no-restricted-syntax
  for (const stage of stages.value) {
    const payload = { name: stage.name.trim(), color: stage.color };
    if (!stage.id) {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await PipelinesAPI.createStage(id, payload);
      orderedIds.push(data.payload.id);
    } else {
      const before = original(stage.id);
      if (before.name !== payload.name || before.color !== payload.color) {
        // eslint-disable-next-line no-await-in-loop
        await PipelinesAPI.updateStage(id, stage.id, payload);
      }
      orderedIds.push(stage.id);
    }
  }
  // eslint-disable-next-line no-restricted-syntax
  for (const stage of removed.value) {
    // eslint-disable-next-line no-await-in-loop
    await PipelinesAPI.deleteStage(id, stage.id, stage.moveTo || undefined);
  }
  await PipelinesAPI.reorderStages(id, orderedIds);
  return { id };
};

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  try {
    const saved = isNew.value ? await createPipeline() : await updatePipeline();
    useAlert(t('PIPELINES.CONFIG.SAVED'));
    dialogRef.value?.close();
    emit('saved', saved.id);
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

const archive = async () => {
  isSaving.value = true;
  try {
    await PipelinesAPI.archive(pipeline.value.id);
    useAlert(t('PIPELINES.CONFIG.ARCHIVED'));
    dialogRef.value?.close();
    emit('archived', pipeline.value.id);
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

// The warning lists the automations that stop working with the pipeline.
const askDelete = async () => {
  deleteConfirmation.value = '';
  affectedAutomations.value = [];
  deleteDialogRef.value?.open();
  try {
    const { data } = await PipelinesAPI.automations(pipeline.value.id);
    affectedAutomations.value = data?.payload || [];
  } catch (error) {
    affectedAutomations.value = [];
  }
};

const confirmDelete = async () => {
  if (deleteConfirmation.value.trim() !== pipeline.value.name) return;
  isSaving.value = true;
  try {
    await PipelinesAPI.delete(pipeline.value.id);
    useAlert(t('PIPELINES.CONFIG.DELETED'));
    deleteDialogRef.value?.close();
    dialogRef.value?.close();
    emit('deleted', pipeline.value.id);
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    :title="
      isNew ? t('PIPELINES.CONFIG.NEW_TITLE') : t('PIPELINES.CONFIG.TITLE')
    "
    :confirm-button-label="t('PIPELINES.CONFIG.SAVE')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    overflow-y-auto
    @confirm="save"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="name"
        :label="t('PIPELINES.CONFIG.NAME')"
        :placeholder="t('PIPELINES.CONFIG.NAME_PLACEHOLDER')"
      />

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('PIPELINES.CONFIG.STAGES') }}
        </span>
        <Draggable
          v-model="stages"
          :item-key="stage => stage.id || stage.key"
          handle=".stage-handle"
          class="flex flex-col gap-2"
        >
          <template #item="{ element: stage }">
            <div class="flex items-center gap-2">
              <span
                class="stage-handle i-lucide-grip-vertical size-4 text-n-slate-10 cursor-grab"
              />
              <input
                v-model="stage.color"
                type="color"
                class="size-8 p-0 border-0 rounded cursor-pointer bg-transparent"
                :aria-label="t('PIPELINES.CONFIG.COLOR')"
              />
              <input
                v-model="stage.name"
                type="text"
                :placeholder="t('PIPELINES.CONFIG.STAGE_PLACEHOLDER')"
                class="reset-base flex-1 h-8 px-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
              />
              <span v-if="stage.count" class="text-xs text-n-slate-11">
                {{
                  t('PIPELINES.STAGE.COUNT_LABEL', stage.count, {
                    count: stage.count,
                  })
                }}
              </span>
              <Button
                v-tooltip.top="t('PIPELINES.CONFIG.REMOVE_STAGE')"
                icon="i-lucide-trash-2"
                slate
                ghost
                xs
                :disabled="stages.length <= 1"
                @click="removeStage(stage)"
              />
            </div>
          </template>
        </Draggable>

        <div
          v-for="stage in closingStages"
          :key="stage.id"
          class="flex items-center gap-2 text-sm text-n-slate-11"
          :title="t('PIPELINES.CONFIG.CLOSING_LOCKED')"
        >
          <span class="i-lucide-lock size-4" />
          <span
            class="inline-block size-3 rounded-full"
            :style="{ backgroundColor: stage.color }"
          />
          {{ stage.name }}
        </div>
        <p v-if="isNew" class="mb-0 text-xs text-n-slate-11">
          {{ t('PIPELINES.CONFIG.CLOSING_HINT') }}
        </p>

        <Button
          :label="t('PIPELINES.CONFIG.ADD_STAGE')"
          icon="i-lucide-plus"
          ghost
          sm
          class="self-start"
          @click="addStage"
        />
      </div>

      <div
        v-for="stage in removed.filter(item => item.count)"
        :key="stage.id"
        class="flex flex-col gap-1 p-3 rounded-lg bg-n-amber-2"
      >
        <span class="text-sm text-n-amber-11">
          {{
            t('PIPELINES.CONFIG.MOVE_CONTACTS', {
              stage: stage.name,
              count: stage.count,
            })
          }}
        </span>
        <select
          v-model="stage.moveTo"
          class="h-8 px-2 text-sm rounded-md border border-n-weak bg-n-input-background text-n-slate-12"
        >
          <option value="" disabled>
            {{ t('PIPELINES.CONFIG.MOVE_CONTACTS_PLACEHOLDER') }}
          </option>
          <option
            v-for="target in keptExistingStages"
            :key="target.id"
            :value="target.id"
          >
            {{ target.name }}
          </option>
        </select>
      </div>

      <div
        v-if="!isNew"
        class="flex items-center gap-2 pt-3 border-t border-n-weak"
      >
        <Button
          :label="t('PIPELINES.CONFIG.ARCHIVE')"
          icon="i-lucide-archive"
          slate
          outline
          sm
          :disabled="isSaving"
          @click="archive"
        />
        <Button
          :label="t('PIPELINES.CONFIG.DELETE')"
          icon="i-lucide-trash-2"
          ruby
          outline
          sm
          :disabled="isSaving"
          @click="askDelete"
        />
      </div>
    </div>
  </Dialog>

  <Dialog
    ref="deleteDialogRef"
    type="alert"
    width="md"
    :title="t('PIPELINES.CONFIG.DELETE_TITLE')"
    :description="
      t('PIPELINES.CONFIG.DELETE_DESCRIPTION', { pipeline: pipeline?.name })
    "
    :confirm-button-label="t('PIPELINES.CONFIG.DELETE_CONFIRM')"
    :disable-confirm-button="deleteConfirmation.trim() !== pipeline?.name"
    :is-loading="isSaving"
    @confirm="confirmDelete"
  >
    <div
      v-if="affectedAutomations.length"
      class="flex flex-col gap-1 p-3 mb-3 rounded-lg bg-n-ruby-2 text-sm text-n-ruby-11"
    >
      <span>{{ t('PIPELINES.CONFIG.DELETE_AUTOMATIONS') }}</span>
      <ul class="m-0 ps-4 list-disc">
        <li v-for="rule in affectedAutomations" :key="rule.id">
          {{ rule.name }}
        </li>
      </ul>
    </div>
    <Input
      v-model="deleteConfirmation"
      :placeholder="pipeline?.name"
      :label="t('PIPELINES.CONFIG.DELETE_TYPE_NAME')"
    />
  </Dialog>
</template>
