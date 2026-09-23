<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters } from 'dashboard/composables/store';
import { debounce } from '@chatwoot/utils';
import FunnelAPI from 'dashboard/api/funnel';
import LossReasonAPI from 'dashboard/api/lossReason';

import FunnelBoard from './components/FunnelBoard.vue';
import FunnelList from './components/FunnelList.vue';
import FunnelOverview from './components/FunnelOverview.vue';
import FunnelConversion from './components/FunnelConversion.vue';
import FunnelFilters from './components/FunnelFilters.vue';
import LossReasonDialog from './components/LossReasonDialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const getters = useStoreGetters();

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

const filters = ref({
  inboxId: '',
  fromDate: '',
  toDate: '',
  hideClosed: false,
  origem: '',
});

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
  if (filters.value.origem) params.origem = filters.value.origem;
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

const moveConversation = async ({ conversationId, stage }) => {
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
  pendingMove.value = null;
  fetchFunnel();
};

const resetFilters = () => {
  filters.value = {
    inboxId: '',
    fromDate: '',
    toDate: '',
    hideClosed: false,
    origem: '',
  };
};

const isEmpty = computed(() => !isLoading.value && stages.value.length === 0);

watch(filters, debouncedFetch, { deep: true });

onMounted(fetchFunnel);
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <header
      class="flex items-center justify-between gap-3 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-heading-2 text-n-slate-12">
        {{ t('FUNNEL.TITLE') }}
      </h1>
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

    <!-- Report-style views (overview / conversion) -->
    <FunnelOverview v-if="viewMode === 'overview'" />
    <FunnelConversion v-else-if="viewMode === 'conversion'" />

    <!-- Stage-layout views (board / list) share the funnel fetch pipeline -->
    <template v-else>
      <FunnelFilters
        v-model:inbox-id="filters.inboxId"
        v-model:from-date="filters.fromDate"
        v-model:to-date="filters.toDate"
        v-model:hide-closed="filters.hideClosed"
        v-model:origem="filters.origem"
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
        :conversations-by-stage="conversationsByStage"
        :average-ticket="accountAverageTicket"
        :locale="accountLocale"
        :loading-more-stage-ids="loadingMoreStageIds"
        @move="moveConversation"
        @load-more="loadMoreForStage"
      />

      <FunnelList
        v-else
        :stages="stages"
        :conversations-by-stage="conversationsByStage"
        :average-ticket="accountAverageTicket"
        :locale="accountLocale"
      />
    </template>

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
