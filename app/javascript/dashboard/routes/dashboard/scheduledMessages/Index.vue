<script setup>
/* global axios */
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
  nextTick,
} from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

// Tabs mirror the model's `enum status`. `draft` is bench-only and never
// fires, so it's not surfaced. Each tab flips the API query to reload from
// scratch — cross-tab counts are not shown up front to keep the endpoint
// cheap; a badge next to "Pendente" is a candidate for a follow-up once we
// see whether operators want it.
const TABS = [
  { id: 'pending', label: 'SCHEDULED.STATUS.PENDING' },
  { id: 'sent', label: 'SCHEDULED.STATUS.SENT' },
  { id: 'held', label: 'SCHEDULED.STATUS.HELD' },
  { id: 'failed', label: 'SCHEDULED.STATUS.FAILED' },
];

const activeStatus = ref('pending');
const items = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const currentPage = ref(1);
const loading = ref(false);
const error = ref(null);

const fetchData = async ({ append = false } = {}) => {
  loading.value = true;
  error.value = null;
  try {
    const res = await axios.get(
      `/api/v1/accounts/${accountId.value}/scheduled_messages`,
      {
        params: { status: activeStatus.value, page: currentPage.value },
      }
    );
    const incoming = res.data.items || [];
    items.value = append ? [...items.value, ...incoming] : incoming;
    meta.value = res.data.meta || meta.value;
  } catch (e) {
    error.value = e.message;
    if (!append) items.value = [];
  } finally {
    loading.value = false;
  }
};

const resetAndFetch = () => {
  currentPage.value = 1;
  fetchData({ append: false });
};

const canLoadMore = computed(
  () => !loading.value && meta.value.current_page < meta.value.total_pages
);

const loadMore = () => {
  if (!canLoadMore.value) return;
  currentPage.value += 1;
  fetchData({ append: true });
};

// Sentinel-driven infinite scroll — same pattern the Media Hub uses.
const sentinel = ref(null);
let observer = null;
const rebindObserver = () => {
  observer?.disconnect();
  if (sentinel.value) observer?.observe(sentinel.value);
};

onMounted(() => {
  observer = new IntersectionObserver(
    entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) loadMore();
      });
    },
    { rootMargin: '400px' }
  );
  resetAndFetch();
});

onBeforeUnmount(() => observer?.disconnect());

watch(sentinel, () => nextTick(rebindObserver));
watch(activeStatus, resetAndFetch);

// Bucket by day so the operator scanning "what's coming today" gets a fast
// visual. Buckets are computed after the fetch — the API already orders by
// scheduled_at asc so today's rows land first for the pending tab.
const groupedItems = computed(() => {
  const buckets = new Map();
  const now = new Date();
  const startOfDay = d => {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    return x;
  };
  const today = startOfDay(now);
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);
  const inSevenDays = new Date(today);
  inSevenDays.setDate(today.getDate() + 7);

  const bucketFor = date => {
    const d = startOfDay(date);
    if (d.getTime() === today.getTime()) return 'Hoje';
    if (d.getTime() === yesterday.getTime()) return 'Ontem';
    if (d.getTime() === tomorrow.getTime()) return 'Amanhã';
    if (d > today && d <= inSevenDays) return 'Próximos 7 dias';
    if (d > inSevenDays) return 'Mais adiante';
    return d.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
  };

  items.value.forEach(item => {
    if (!item.scheduled_at) return;
    const key = bucketFor(item.scheduled_at);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(item);
  });

  return Array.from(buckets, ([label, rows]) => ({ label, rows }));
});

const formatDateTime = value =>
  value
    ? new Date(value).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

const contactSubtitle = item => {
  const parts = [item.contact?.phone_number, item.inbox?.name].filter(Boolean);
  return parts.join(' · ');
};

const goToConversation = item => {
  if (!item.conversation_id) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${item.conversation_id}`
  );
};

const statusPillClass = status => {
  switch (status) {
    case 'pending':
      return 'bg-n-amber-3 text-n-amber-11';
    case 'sent':
      return 'bg-n-emerald-3 text-n-emerald-11';
    case 'failed':
      return 'bg-n-ruby-3 text-n-ruby-11';
    case 'held':
      return 'bg-n-slate-3 text-n-slate-11';
    default:
      return 'bg-n-slate-3 text-n-slate-11';
  }
};
</script>

<template>
  <div class="w-full h-full overflow-hidden bg-n-slate-1">
    <div class="mx-auto max-w-5xl h-full flex flex-col bg-n-solid-1 shadow-sm">
      <!-- Header -->
      <div class="border-b border-n-slate-4 px-6 pt-5 pb-3">
        <h1 class="text-2xl font-semibold text-n-slate-12 leading-tight">
          {{ t('SCHEDULED.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-1 mb-4">
          {{ t('SCHEDULED.SUBTITLE') }}
        </p>
        <nav class="flex gap-6 mb-[-1px]">
          <button
            v-for="tab in TABS"
            :key="tab.id"
            type="button"
            class="pb-3 pt-1 text-sm border-b-2 border-transparent text-n-slate-11 hover:text-n-slate-12"
            :class="{
              'border-n-slate-12 text-n-slate-12 font-semibold':
                activeStatus === tab.id,
            }"
            @click="activeStatus = tab.id"
          >
            {{ t(tab.label) }}
          </button>
        </nav>
      </div>

      <!-- Content -->
      <div class="flex-1 overflow-y-auto px-6 py-5">
        <p v-if="loading && !items.length" class="text-sm text-n-slate-11">
          {{ t('SCHEDULED.LOADING') }}
        </p>
        <p v-else-if="error" class="text-sm text-n-ruby-9">
          {{ error }}
        </p>
        <p v-else-if="!items.length" class="py-16 text-center text-n-slate-11">
          {{ t('SCHEDULED.EMPTY') }}
        </p>

        <template v-else>
          <div
            v-for="group in groupedItems"
            :key="group.label"
            class="mb-6 last:mb-0"
          >
            <p class="text-base font-semibold text-n-slate-12 mb-1">
              {{ group.label }}
            </p>
            <p class="text-xs text-n-slate-11 mb-3">
              {{ group.rows.length }} {{ t('SCHEDULED.ITEMS_LABEL') }}
            </p>

            <ul
              class="flex flex-col divide-y divide-n-slate-3 border border-n-slate-3 rounded-lg overflow-hidden"
            >
              <li
                v-for="item in group.rows"
                :key="item.id"
                class="flex items-start gap-3 p-3 hover:bg-n-slate-2 cursor-pointer"
                @click="goToConversation(item)"
              >
                <div
                  class="w-10 h-10 flex-shrink-0 rounded-full bg-n-slate-3 flex items-center justify-center overflow-hidden"
                >
                  <img
                    v-if="item.contact?.thumbnail"
                    :src="item.contact.thumbnail"
                    :alt="item.contact?.name || ''"
                    class="w-full h-full object-cover"
                  />
                  <span v-else class="text-xs font-semibold text-n-slate-11">
                    {{ (item.contact?.name || '?').slice(0, 2).toUpperCase() }}
                  </span>
                </div>
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span
                      class="text-sm font-semibold text-n-slate-12 truncate"
                    >
                      {{ item.contact?.name || t('SCHEDULED.NO_CONTACT_NAME') }}
                    </span>
                    <span
                      class="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded-md"
                      :class="statusPillClass(item.status)"
                    >
                      {{ t(`SCHEDULED.STATUS.${item.status.toUpperCase()}`) }}
                    </span>
                  </div>
                  <p class="text-xs text-n-slate-11 mt-0.5 truncate">
                    {{ contactSubtitle(item) }}
                  </p>
                  <p
                    class="text-sm text-n-slate-12 mt-1.5 line-clamp-2 break-words"
                  >
                    {{ item.content || t('SCHEDULED.NO_CONTENT') }}
                  </p>
                </div>
                <div
                  class="text-right text-xs text-n-slate-11 flex-shrink-0 pl-2"
                >
                  <div class="font-medium text-n-slate-12">
                    {{ formatDateTime(item.scheduled_at) }}
                  </div>
                  <div class="mt-0.5">
                    {{ item.author?.name || '' }}
                  </div>
                </div>
              </li>
            </ul>
          </div>
          <div ref="sentinel" class="h-4" />
          <p
            v-if="loading && items.length"
            class="py-4 text-center text-xs text-n-slate-11"
          >
            {{ t('SCHEDULED.LOADING') }}
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
