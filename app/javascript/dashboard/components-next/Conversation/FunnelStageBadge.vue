<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import LossReasonAPI from 'dashboard/api/lossReason';
import LossReasonDialog from 'dashboard/routes/dashboard/funnel/components/LossReasonDialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';

const props = defineProps({
  conversationId: { type: Number, required: true },
  stage: { type: Object, default: null },
});

const { t } = useI18n();
const store = useStore();

const lossReasons = ref([]);
const isOpen = ref(false);
const isMoving = ref(false);
const isSubmittingLossReason = ref(false);
const pendingStage = ref(null);
const lossReasonDialogRef = ref(null);

const currentStageName = computed(
  () => props.stage?.name || t('CONVERSATION.FUNNEL_STAGE.EMPTY')
);

// Shared with the conversation filter: the list is fetched once for the whole
// session instead of on every conversation opened.
const stages = useMapGetter('funnelStages/getFunnelStages');

const fetchLossReasons = async () => {
  if (lossReasons.value.length) return;
  try {
    const { data } = await LossReasonAPI.get();
    lossReasons.value = (data?.payload || []).filter(reason => reason.active);
  } catch (error) {
    lossReasons.value = [];
  }
};

onMounted(() => store.dispatch('funnelStages/get'));

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const applyStage = async (stage, lossReasonId) => {
  isMoving.value = true;
  try {
    await store.dispatch('moveToFunnelStage', {
      conversationId: props.conversationId,
      stage,
      lossReasonId,
    });
    useAlert(t('CONVERSATION.FUNNEL_STAGE.MOVED', { stage: stage.name }));
  } catch (error) {
    useAlert(t('CONVERSATION.FUNNEL_STAGE.MOVE_ERROR'));
  } finally {
    isMoving.value = false;
  }
};

// The stage that comes after the current one, in the order the funnel is
// configured. It is what the play button advances to, the same way the kanban
// walks a card to the right.
const nextStage = computed(() => {
  if (!stages.value.length) return null;
  if (!props.stage) return stages.value[0];

  const currentIndex = stages.value.findIndex(
    option => option.id === props.stage.id
  );
  if (currentIndex === -1) return stages.value[0];

  return stages.value[currentIndex + 1] || null;
});

const selectStage = async stage => {
  isOpen.value = false;
  if (stage.id === props.stage?.id) return;

  // A stage that demands a loss reason is refused by the backend without one,
  // so the same dialog the kanban uses asks for it before moving.
  if (stage.requires_loss_reason) {
    pendingStage.value = stage;
    await fetchLossReasons();
    lossReasonDialogRef.value?.open();
    return;
  }

  await applyStage(stage);
};

const advance = async () => {
  if (!nextStage.value) return;

  await selectStage(nextStage.value);
};

const onLossReasonConfirm = async lossReasonId => {
  if (!pendingStage.value) return;
  isSubmittingLossReason.value = true;
  try {
    await applyStage(pendingStage.value, lossReasonId);
    lossReasonDialogRef.value?.close();
    pendingStage.value = null;
  } finally {
    isSubmittingLossReason.value = false;
  }
};

const onLossReasonClose = () => {
  pendingStage.value = null;
};
</script>

<template>
  <div class="relative flex-shrink-0">
    <ButtonGroup
      class="flex-shrink-0 rounded-lg shadow outline outline-1 outline-n-container"
    >
      <Button
        size="sm"
        color="slate"
        no-animation
        class="ltr:rounded-r-none rtl:rounded-l-none !outline-0 max-w-[11rem]"
        :is-loading="isMoving"
        :title="t('CONVERSATION.FUNNEL_STAGE.TOOLTIP')"
        @click.stop.prevent="toggle"
      >
        <template #icon>
          <span
            class="inline-block w-2 h-2 rounded-full flex-shrink-0"
            :style="{ backgroundColor: stage?.color || 'var(--s-300)' }"
          />
        </template>
        <span class="truncate">{{ currentStageName }}</span>
      </Button>
      <Button
        v-tooltip="
          nextStage
            ? t('CONVERSATION.FUNNEL_STAGE.ADVANCE_TO', {
                stage: nextStage.name,
              })
            : t('CONVERSATION.FUNNEL_STAGE.ADVANCE_DISABLED')
        "
        icon="i-lucide-play"
        size="sm"
        color="slate"
        no-animation
        class="ltr:rounded-l-none rtl:rounded-r-none !outline-0"
        :disabled="!nextStage || isMoving"
        @click.stop.prevent="advance"
      />
    </ButtonGroup>

    <div
      v-if="isOpen"
      class="absolute right-0 z-50 mt-1 w-56 max-h-72 overflow-y-auto rounded-lg bg-n-solid-2 outline outline-1 outline-n-container shadow-lg py-1"
    >
      <button
        v-for="option in stages"
        :key="option.id"
        type="button"
        class="flex items-center gap-2 w-full px-3 py-1.5 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
        @click.stop.prevent="selectStage(option)"
      >
        <span
          class="inline-block w-2.5 h-2.5 rounded-full flex-shrink-0"
          :style="{ backgroundColor: option.color }"
        />
        <span class="truncate flex-1">{{ option.name }}</span>
        <Icon
          v-if="option.id === stage?.id"
          icon="i-lucide-check"
          class="size-4 text-n-slate-11 flex-shrink-0"
        />
      </button>
      <p v-if="!stages.length" class="px-3 py-2 text-xs text-n-slate-11">
        {{ t('CONVERSATION.FUNNEL_STAGE.NO_STAGES') }}
      </p>
    </div>

    <LossReasonDialog
      ref="lossReasonDialogRef"
      :reasons="lossReasons"
      :is-submitting="isSubmittingLossReason"
      @confirm="onLossReasonConfirm"
      @close="onLossReasonClose"
    />
  </div>
</template>
