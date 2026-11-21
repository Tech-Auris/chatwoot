<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'vuex';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { debounce } from '@chatwoot/utils';
import FunnelAPI from 'dashboard/api/funnel';
import LossReasonAPI from 'dashboard/api/lossReason';
import PipelinesAPI from 'dashboard/api/pipelines';
import Button from 'dashboard/components-next/button/Button.vue';
import PipelineSelector from './components/PipelineSelector.vue';
import PipelineCard from './components/PipelineCard.vue';
import PipelineList from './components/PipelineList.vue';
import PipelineConfigDialog from './components/PipelineConfigDialog.vue';
import PipelineAddContactDialog from './components/PipelineAddContactDialog.vue';
import PipelineConversion from './components/PipelineConversion.vue';

import FunnelBoard from './components/FunnelBoard.vue';
import SaveAsAudienceDialog from 'dashboard/routes/dashboard/marketing/audiences/components/SaveAsAudienceDialog.vue';
import FunnelList from './components/FunnelList.vue';
import FunnelOverview from './components/FunnelOverview.vue';
import FunnelConversion from './components/FunnelConversion.vue';
import FunnelFilters from './components/FunnelFilters.vue';
import LossReasonDialog from './components/LossReasonDialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const { isAdmin, isManager } = useAdmin();
const canManagePipelines = computed(() => isAdmin.value || isManager.value);

// null = Agendamento, the default funnel: per conversation, stages owned by
// Auris. Any other value is a clinic pipeline (per contact). The Funil always
// opens on the Agendamento — the choice is not remembered.
const selectedPipelineId = ref(null);
const isClinicPipeline = computed(() => selectedPipelineId.value !== null);
const selectedPipeline = computed(() =>
  getters['pipelines/getPipeline'].value(selectedPipelineId.value)
);

// 'board' and 'list' share the FunnelFilters / fetchFunnel pipeline below
// (real-time stage layout with conversations grouped by stage). 'overview'
// and 'conversion' are report-style views that bring their own date filter
// and Vuex-backed fetch, so they sit outside that pipeline.
const VIEW_MODES = ['board', 'list', 'overview', 'conversion'];
const VIEW_ICONS = {
  board: 'i-lucide-columns-3',
  list: 'i-lucide-list',
  overview: 'i-lucide-table',
  conversion: 'i-lucide-trending-down',
};
const viewMode = ref('board');

const isLoading = ref(false);
const stages = ref([]);
const conversationsByStage = ref({});
// Per-stage pagination cursor — used by the `load-more` handler to know
// which page of a column to fetch next. Reset whenever the whole board
// reloads (a filter change, a manual refresh, an error retry).
const stagePageByStageId = ref({});
const loadingMoreStageIds = ref([]);

const accountId = computed(() => getters.getCurrentAccountId.value);
const account = computed(() =>
  getters['accounts/getAccount'].value(accountId.value)
);
const accountLocale = computed(() => account.value?.locale || 'en');
const accountAverageTicket = computed(
  () => Number(account.value?.average_ticket) || 0
);

// Board and list open with closed stages and resolved conversations hidden;
// "Limpar filtros" goes back to this same state.
const DEFAULT_FILTERS = {
  inboxId: '',
  fromDate: '',
  toDate: '',
  hideClosed: true,
  hideResolved: true,
  origem: '',
  label: '',
};
const filters = ref({ ...DEFAULT_FILTERS });

const setViewMode = mode => {
  if (!VIEW_MODES.includes(mode)) return;
  viewMode.value = mode;
};

const buildQueryParams = () => {
  const params = {};
  if (filters.value.inboxId) params.inbox_id = filters.value.inboxId;
  if (filters.value.fromDate)
    params.from = `${filters.value.fromDate}T00:00:00`;
  if (filters.value.toDate) params.to = `${filters.value.toDate}T23:59:59`;
  if (filters.value.hideClosed) params.hide_closed = 'true';
  if (filters.value.hideResolved) params.hide_resolved = 'true';
  if (filters.value.origem) params.origem = filters.value.origem;
  if (filters.value.label) params.label = filters.value.label;
  return params;
};

const fetchFunnel = async () => {
  isLoading.value = true;
  try {
    const { data } = await FunnelAPI.get(buildQueryParams());
    stages.value = data?.payload?.stages || [];
    const grouped = {};
    const pages = {};
    stages.value.forEach(stage => {
      grouped[stage.name] = stage.conversations || [];
      pages[stage.id] = 1;
    });
    conversationsByStage.value = grouped;
    stagePageByStageId.value = pages;
    loadingMoreStageIds.value = [];
  } catch (error) {
    useAlert(t('FUNNEL.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

// Called when the operator clicks "Carregar mais" at the bottom of a
// column. Fetches the next page of that column only and appends the
// incoming cards to `conversationsByStage[stage.name]`.
const loadMoreForStage = async stage => {
  if (!stage || loadingMoreStageIds.value.includes(stage.id)) return;
  loadingMoreStageIds.value = [...loadingMoreStageIds.value, stage.id];
  const nextPage = (stagePageByStageId.value[stage.id] || 1) + 1;
  try {
    const { data } = await FunnelAPI.stageConversations(
      stage.id,
      nextPage,
      buildQueryParams()
    );
    const incoming = data?.payload?.conversations || [];
    const existing = conversationsByStage.value[stage.name] || [];
    conversationsByStage.value = {
      ...conversationsByStage.value,
      [stage.name]: [...existing, ...incoming],
    };
    stagePageByStageId.value = {
      ...stagePageByStageId.value,
      [stage.id]: nextPage,
    };
    stages.value = stages.value.map(s =>
      s.id === stage.id ? { ...s, has_more: data?.payload?.meta?.has_more } : s
    );
  } catch (error) {
    useAlert(t('FUNNEL.LOAD_ERROR'));
  } finally {
    loadingMoreStageIds.value = loadingMoreStageIds.value.filter(
      id => id !== stage.id
    );
  }
};

const debouncedFetch = debounce(fetchFunnel, 300);

const lossReasonDialogRef = ref(null);
const lossReasons = ref([]);
const isLoadingLossReasons = ref(false);
const isSubmittingLossReason = ref(false);
const pendingMove = ref(null);

const fetchLossReasons = async () => {
  if (lossReasons.value.length) return;
  isLoadingLossReasons.value = true;
  try {
    const { data } = await LossReasonAPI.get();
    lossReasons.value = (data?.payload || []).filter(r => r.active);
  } finally {
    isLoadingLossReasons.value = false;
  }
};

const optimisticMove = ({ conversationId, fromStageName, toStageName }) => {
  const movedConversation = (
    conversationsByStage.value[fromStageName] || []
  ).find(c => c.id === conversationId);
  if (!movedConversation) return null;

  conversationsByStage.value = {
    ...conversationsByStage.value,
    [fromStageName]: conversationsByStage.value[fromStageName].filter(
      c => c.id !== conversationId
    ),
    [toStageName]: [
      ...(conversationsByStage.value[toStageName] || []),
      movedConversation,
    ],
  };

  stages.value = stages.value.map(s => {
    if (s.name === fromStageName)
      return { ...s, count: Math.max(0, (s.count || 0) - 1) };
    if (s.name === toStageName) return { ...s, count: (s.count || 0) + 1 };
    return s;
  });

  return movedConversation;
};

const callMove = async ({ conversationId, toStageName, lossReasonId }) => {
  try {
    await FunnelAPI.move({
      conversationId,
      stage: toStageName,
      source: 'web',
      lossReasonId,
    });
  } catch (error) {
    useAlert(t('FUNNEL.MOVE.ERROR'));
    await fetchFunnel();
  }
};

const moveConversation = async ({ id: conversationId, stage }) => {
  let sourceStageName = null;
  Object.entries(conversationsByStage.value).some(([stageName, list]) => {
    const idx = list.findIndex(c => c.id === conversationId);
    if (idx === -1) return false;
    sourceStageName = stageName;
    return true;
  });

  if (!sourceStageName || sourceStageName === stage) return;

  const targetStage = stages.value.find(s => s.name === stage);
  if (!targetStage) return;

  if (targetStage.requires_loss_reason) {
    pendingMove.value = {
      conversationId,
      fromStageName: sourceStageName,
      toStageName: stage,
    };
    fetchLossReasons();
    lossReasonDialogRef.value?.open();
    return;
  }

  optimisticMove({
    conversationId,
    fromStageName: sourceStageName,
    toStageName: stage,
  });
  await callMove({ conversationId, toStageName: stage });
};

const onLossReasonConfirm = async lossReasonId => {
  if (!pendingMove.value) return;
  if (pendingMove.value.entryId) {
    // eslint-disable-next-line no-use-before-define
    await confirmPipelineLoss(lossReasonId);
    return;
  }
  isSubmittingLossReason.value = true;
  try {
    optimisticMove(pendingMove.value);
    await callMove({
      conversationId: pendingMove.value.conversationId,
      toStageName: pendingMove.value.toStageName,
      lossReasonId,
    });
    lossReasonDialogRef.value?.close();
    pendingMove.value = null;
  } finally {
    isSubmittingLossReason.value = false;
  }
};

const onLossReasonClose = () => {
  if (!pendingMove.value) return;
  const wasPipelineMove = !!pendingMove.value.entryId;
  pendingMove.value = null;
  // eslint-disable-next-line no-use-before-define
  if (wasPipelineMove) fetchPipelineBoard();
  else fetchFunnel();
};

const resetFilters = () => {
  filters.value = { ...DEFAULT_FILTERS };
};

const isEmpty = computed(() => !isLoading.value && stages.value.length === 0);

watch(filters, debouncedFetch, { deep: true });

// "Salvar como público" on a column: its stage plus the inbox and origin in
// use; the period becomes the audience's window.
const saveAsAudienceDialogRef = ref(null);
const audienceStage = ref(null);
const condition = (key, value) => ({
  attribute_key: key,
  filter_operator: 'equal_to',
  values: [value],
});
const audienceRule = computed(() => {
  const { inboxId, origem, label } = filters.value;
  return [
    condition('funnel_stage_id', audienceStage.value.id),
    inboxId && condition('inbox_id', Number(inboxId)),
    origem && condition('origem', origem),
    label && condition('labels', label),
  ].filter(Boolean);
});
const audienceWindow = computed(() => {
  const { fromDate, toDate } = filters.value;
  return fromDate && toDate
    ? { type: 'range', from: fromDate, to: toDate }
    : { type: 'all' };
});
const openSaveAsAudience = async stage => {
  audienceStage.value = stage;
  await nextTick();
  saveAsAudienceDialogRef.value?.open();
};

// ---- Clinic pipelines -------------------------------------------------
const DEFAULT_PIPELINE_FILTERS = {
  fromDate: '',
  toDate: '',
  hideClosed: true,
  label: '',
  source: '',
};
const pipelineFilters = ref({ ...DEFAULT_PIPELINE_FILTERS });
const pipelineStages = ref([]);
const entriesByStage = ref({});
const entryPageByStageId = ref({});
const loadingMoreEntryStageIds = ref([]);

const buildPipelineParams = () => {
  const { fromDate, toDate, hideClosed, label, source } = pipelineFilters.value;
  const params = {};
  if (fromDate) params.from = `${fromDate}T00:00:00`;
  if (toDate) params.to = `${toDate}T23:59:59`;
  if (hideClosed) params.hide_closed = 'true';
  if (label) params.label = label;
  if (source) params.source = source;
  return params;
};

const fetchPipelineBoard = async () => {
  if (!isClinicPipeline.value) return;
  try {
    const { data } = await PipelinesAPI.board(
      selectedPipelineId.value,
      buildPipelineParams()
    );
    pipelineStages.value = data?.payload?.stages || [];
    entriesByStage.value = Object.fromEntries(
      pipelineStages.value.map(stage => [stage.name, stage.entries || []])
    );
    entryPageByStageId.value = Object.fromEntries(
      pipelineStages.value.map(stage => [stage.id, 1])
    );
  } catch (error) {
    useAlert(t('FUNNEL.LOAD_ERROR'));
  }
};

const loadMoreEntries = async stage => {
  if (loadingMoreEntryStageIds.value.includes(stage.id)) return;
  loadingMoreEntryStageIds.value = [
    ...loadingMoreEntryStageIds.value,
    stage.id,
  ];
  const nextPage = (entryPageByStageId.value[stage.id] || 1) + 1;
  try {
    const { data } = await PipelinesAPI.stageEntries(
      selectedPipelineId.value,
      stage.id,
      nextPage,
      buildPipelineParams()
    );
    entriesByStage.value = {
      ...entriesByStage.value,
      [stage.name]: [
        ...(entriesByStage.value[stage.name] || []),
        ...(data?.payload?.entries || []),
      ],
    };
    entryPageByStageId.value = {
      ...entryPageByStageId.value,
      [stage.id]: nextPage,
    };
    pipelineStages.value = pipelineStages.value.map(s =>
      s.id === stage.id ? { ...s, has_more: data?.payload?.meta?.has_more } : s
    );
  } catch (error) {
    useAlert(t('FUNNEL.LOAD_ERROR'));
  } finally {
    loadingMoreEntryStageIds.value = loadingMoreEntryStageIds.value.filter(
      id => id !== stage.id
    );
  }
};

const stageNameOfEntry = entryId =>
  Object.keys(entriesByStage.value).find(name =>
    entriesByStage.value[name].some(entry => entry.id === entryId)
  );

// Moves the card right away, the way the Agendamento board does; the API
// answer then replaces it (new time on the stage, loss reason).
const placeEntry = (entry, toStageName) => {
  const fromStageName = stageNameOfEntry(entry.id);
  const without = name =>
    (entriesByStage.value[name] || []).filter(item => item.id !== entry.id);
  entriesByStage.value = {
    ...entriesByStage.value,
    [fromStageName]: without(fromStageName),
    [toStageName]: [entry, ...without(toStageName)],
  };
  pipelineStages.value = pipelineStages.value.map(stage => {
    if (fromStageName === toStageName) return stage;
    if (stage.name === fromStageName)
      return { ...stage, count: Math.max(0, (stage.count || 0) - 1) };
    if (stage.name === toStageName)
      return { ...stage, count: (stage.count || 0) + 1 };
    return stage;
  });
};

const callPipelineMove = async ({ entryId, stageId, lossReasonId }) => {
  const target = pipelineStages.value.find(stage => stage.id === stageId);
  const current = entriesByStage.value[stageNameOfEntry(entryId)].find(
    entry => entry.id === entryId
  );
  placeEntry(current, target.name);
  try {
    const { data } = await PipelinesAPI.moveEntry(entryId, {
      stageId,
      lossReasonId,
    });
    placeEntry(data.payload, target.name);
  } catch (error) {
    useAlert(error?.response?.data?.message || t('PIPELINES.MOVE_ERROR'));
    await fetchPipelineBoard();
  }
};

const moveEntry = async ({ id: entryId, stage: stageName }) => {
  const target = pipelineStages.value.find(stage => stage.name === stageName);
  if (!target || stageNameOfEntry(entryId) === stageName) return;
  if (target.kind === 'lost') {
    pendingMove.value = { entryId, stageId: target.id };
    fetchLossReasons();
    lossReasonDialogRef.value?.open();
    return;
  }
  await callPipelineMove({ entryId, stageId: target.id });
};

const confirmPipelineLoss = async lossReasonId => {
  isSubmittingLossReason.value = true;
  try {
    await callPipelineMove({ ...pendingMove.value, lossReasonId });
    pendingMove.value = null;
    lossReasonDialogRef.value?.close();
  } finally {
    isSubmittingLossReason.value = false;
  }
};

const refreshPipelines = () => store.dispatch('pipelines/get', { force: true });

// A card of another pipeline changed ("Adicionar a"): the counts of the
// selector change; the board only when it is the one on screen.
const onPipelineMembershipChanged = pipelineId => {
  refreshPipelines();
  if (pipelineId === selectedPipelineId.value) fetchPipelineBoard();
};

const configDialogRef = ref(null);
const addContactDialogRef = ref(null);

const openNewPipeline = () => configDialogRef.value?.open(null);
const openPipelineConfig = () => {
  const counts = Object.fromEntries(
    pipelineStages.value.map(stage => [stage.id, stage.count || 0])
  );
  configDialogRef.value?.open(selectedPipeline.value, counts);
};

const onPipelineSaved = async pipelineId => {
  await refreshPipelines();
  if (selectedPipelineId.value === pipelineId) fetchPipelineBoard();
  else selectedPipelineId.value = pipelineId;
};

const onPipelineGone = async () => {
  selectedPipelineId.value = null;
  await refreshPipelines();
};

// Switching pipelines clears the board (spinner) and resets the filters,
// which fetches the new board through the filters watcher.
watch(selectedPipelineId, () => {
  pipelineStages.value = [];
  entriesByStage.value = {};
  pipelineFilters.value = { ...DEFAULT_PIPELINE_FILTERS };
});
watch(pipelineFilters, debounce(fetchPipelineBoard, 300), { deep: true });

onMounted(() => {
  fetchFunnel();
  store.dispatch('pipelines/get');
});
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <header
      class="flex flex-wrap items-center gap-3 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center gap-3 min-w-0">
        <h1 class="text-heading-2 text-n-slate-12">
          {{ t('FUNNEL.TITLE') }}
        </h1>
        <PipelineSelector
          v-model="selectedPipelineId"
          :can-manage="canManagePipelines"
          @create="openNewPipeline"
        />
      </div>
      <div class="flex items-center gap-2 ms-auto">
        <Button
          v-if="isClinicPipeline"
          :label="t('PIPELINES.ADD_CONTACT.BUTTON')"
          icon="i-lucide-user-plus"
          sm
          @click="addContactDialogRef?.open()"
        />
        <Button
          v-if="canManagePipelines"
          v-tooltip.bottom="
            isClinicPipeline ? '' : t('PIPELINES.CONFIG.AGENDAMENTO_LOCKED')
          "
          :label="t('PIPELINES.CONFIG.BUTTON')"
          icon="i-lucide-settings-2"
          slate
          outline
          sm
          :disabled="!isClinicPipeline"
          @click="openPipelineConfig"
        />
      </div>
      <div
        class="inline-flex items-center gap-1 p-1 rounded-lg bg-n-alpha-2"
        role="group"
        :aria-label="t('FUNNEL.VIEW_MODE.ARIA_LABEL')"
      >
        <button
          v-for="mode in VIEW_MODES"
          :key="mode"
          type="button"
          class="inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-sm font-medium transition-colors"
          :class="
            viewMode === mode
              ? 'bg-n-surface-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setViewMode(mode)"
        >
          <span :class="VIEW_ICONS[mode]" class="size-4" />
          {{ t(`FUNNEL.VIEW_MODE.${mode.toUpperCase()}`) }}
        </button>
      </div>
    </header>

    <!-- Clinic pipeline reports -->
    <FunnelOverview
      v-if="isClinicPipeline && viewMode === 'overview'"
      :key="`overview-${selectedPipelineId}`"
      :pipeline-id="selectedPipelineId"
    />
    <PipelineConversion
      v-else-if="isClinicPipeline && viewMode === 'conversion'"
      :key="`conversion-${selectedPipelineId}`"
      :pipeline-id="selectedPipelineId"
    />

    <!-- Clinic pipeline board / list (per contact) -->
    <template v-else-if="isClinicPipeline">
      <FunnelFilters
        v-model:from-date="pipelineFilters.fromDate"
        v-model:to-date="pipelineFilters.toDate"
        v-model:hide-closed="pipelineFilters.hideClosed"
        v-model:label="pipelineFilters.label"
        v-model:source="pipelineFilters.source"
        contact-mode
        @reset="pipelineFilters = { ...DEFAULT_PIPELINE_FILTERS }"
      />
      <div
        v-if="!pipelineStages.length"
        class="flex items-center justify-center flex-1 text-n-slate-11"
      >
        <Spinner />
      </div>
      <FunnelBoard
        v-else-if="viewMode === 'board'"
        :stages="pipelineStages"
        :items-by-stage="entriesByStage"
        count-label-key="PIPELINES.STAGE.COUNT_LABEL"
        :show-save-as-audience="false"
        :loading-more-stage-ids="loadingMoreEntryStageIds"
        @move="moveEntry"
        @load-more="loadMoreEntries"
      >
        <template #card="{ item }">
          <PipelineCard :entry="item" @changed="onPipelineMembershipChanged" />
        </template>
      </FunnelBoard>
      <PipelineList
        v-else
        :stages="pipelineStages"
        :entries-by-stage="entriesByStage"
      />
    </template>

    <!-- Report-style views (overview / conversion) -->
    <FunnelOverview v-else-if="viewMode === 'overview'" />
    <FunnelConversion v-else-if="viewMode === 'conversion'" />

    <!-- Stage-layout views (board / list) share the funnel fetch pipeline -->
    <template v-else>
      <FunnelFilters
        v-model:inbox-id="filters.inboxId"
        v-model:from-date="filters.fromDate"
        v-model:to-date="filters.toDate"
        v-model:hide-closed="filters.hideClosed"
        v-model:hide-resolved="filters.hideResolved"
        v-model:origem="filters.origem"
        v-model:label="filters.label"
        @reset="resetFilters"
      />

      <div
        v-if="isLoading"
        class="flex items-center justify-center flex-1 text-n-slate-11"
      >
        <Spinner />
      </div>

      <div
        v-else-if="isEmpty"
        class="flex items-center justify-center flex-1 text-n-slate-11 px-6 text-center"
      >
        {{ t('FUNNEL.EMPTY_STATE') }}
      </div>

      <FunnelBoard
        v-else-if="viewMode === 'board'"
        :stages="stages"
        :items-by-stage="conversationsByStage"
        :average-ticket="accountAverageTicket"
        :locale="accountLocale"
        :loading-more-stage-ids="loadingMoreStageIds"
        @move="moveConversation"
        @load-more="loadMoreForStage"
        @save-as-audience="openSaveAsAudience"
      />

      <FunnelList
        v-else
        :stages="stages"
        :conversations-by-stage="conversationsByStage"
        :average-ticket="accountAverageTicket"
        :locale="accountLocale"
      />
    </template>

    <SaveAsAudienceDialog
      ref="saveAsAudienceDialogRef"
      :rule="audienceStage ? audienceRule : []"
      :window="audienceWindow"
      :pick-loss-reason="!!audienceStage?.requires_loss_reason"
    />

    <PipelineConfigDialog
      ref="configDialogRef"
      @saved="onPipelineSaved"
      @archived="onPipelineGone"
      @deleted="onPipelineGone"
    />
    <PipelineAddContactDialog
      ref="addContactDialogRef"
      :pipeline="selectedPipeline"
      @added="onPipelineMembershipChanged(selectedPipelineId)"
    />

    <LossReasonDialog
      ref="lossReasonDialogRef"
      :reasons="lossReasons"
      :is-loading="isLoadingLossReasons"
      :is-submitting="isSubmittingLossReason"
      @confirm="onLossReasonConfirm"
      @close="onLossReasonClose"
    />
  </section>
</template>
