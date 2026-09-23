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
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

// One tab per attachment kind — the umbrella "Mídias" was split so the
// operator jumps straight to Imagens / Vídeos / Áudios instead of scrolling
// past unrelated types to find what they want.
const TABS = [
  { id: 'image', label: 'Imagens' },
  { id: 'video', label: 'Vídeos' },
  { id: 'audio', label: 'Áudios' },
  { id: 'document', label: 'Documentos' },
  { id: 'link', label: 'Links' },
];

const activeTab = ref('image');
const items = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const currentPage = ref(1);
const loading = ref(false);
const error = ref(null);
// Videos that failed to load a first-frame poster — the placeholder icon
// takes over for those ids. `<video preload="metadata">` extracts a frame
// natively when the file is served by our own domain and CORS lets it
// through; a WhatsApp CDN URL often fails silently, which is what this
// set catches.
const videoErrors = ref(new Set());
const markVideoError = id => {
  const next = new Set(videoErrors.value);
  next.add(id);
  videoErrors.value = next;
};
const videoErrored = id => videoErrors.value.has(id);

const isMediaGrid = computed(() =>
  ['image', 'video', 'audio'].includes(activeTab.value)
);

const subtitle = computed(() => {
  switch (activeTab.value) {
    case 'image':
      return 'Imagens de todas as conversas';
    case 'video':
      return 'Vídeos de todas as conversas';
    case 'audio':
      return 'Áudios de todas as conversas';
    case 'document':
      return 'Documentos de todas as conversas';
    default:
      return 'Links de todas as conversas';
  }
});

// The search box's help text picks up "nome do arquivo" on the docs tab
// since documents are the one place a filename is the primary handle.
const searchPlaceholder = computed(() => {
  if (activeTab.value === 'document')
    return t('MEDIA_HUB.SEARCH.PLACEHOLDER_DOCUMENT');
  return t('MEDIA_HUB.SEARCH.PLACEHOLDER');
});

// Search / sort state kept up here because the display pipeline below
// (displayItems → groupedItems) depends on them. Toggle helpers live
// next to the multi-select state below.
const searchMode = ref(false);
const searchQuery = ref('');
const sortMenuOpen = ref(false);
const senderFilter = ref('all');
const sortOrder = ref('newest');

// Filtered + sorted items feed the grouping. Kept as one computed so
// the group headers update in lockstep with the sender / order picks.
const displayItems = computed(() => {
  let list = items.value;
  if (searchQuery.value.trim()) {
    const needle = searchQuery.value.trim().toLowerCase();
    list = list.filter(it =>
      [it.sender_name, it.caption, it.url, it.fallback_title]
        .filter(Boolean)
        .some(v => v.toLowerCase().includes(needle))
    );
  }
  if (senderFilter.value === 'me') {
    list = list.filter(it => (it.sender_name || '').toLowerCase() === 'você');
  } else if (senderFilter.value === 'others') {
    list = list.filter(it => (it.sender_name || '').toLowerCase() !== 'você');
  }
  const sorted = [...list];
  if (sortOrder.value === 'oldest') {
    sorted.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  } else if (sortOrder.value === 'largest') {
    sorted.sort((a, b) => (b.file_size || 0) - (a.file_size || 0));
  } else {
    sorted.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  }
  return sorted;
});

// Bucket by date the same way WhatsApp Business does — Hoje, Ontem,
// Semana passada (the previous 7 days), then straight into monthly
// buckets. The intermediate "Esta semana" label we had before is gone;
// anything from earlier this week that isn't today or yesterday joins
// "Semana passada" so the sections read the way the operator expects.
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
  const sevenDaysAgo = new Date(today);
  sevenDaysAgo.setDate(today.getDate() - 7);

  const bucketFor = date => {
    const d = startOfDay(date);
    if (d.getTime() === today.getTime()) return 'Hoje';
    if (d.getTime() === yesterday.getTime()) return 'Ontem';
    if (d >= sevenDaysAgo) return 'Semana passada';
    return d.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
  };

  displayItems.value.forEach(item => {
    const key = bucketFor(item.created_at);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(item);
  });

  return Array.from(buckets, ([label, rows]) => ({ label, rows }));
});

const extensionLabel = () => 'Arquivo';

const formatBytes = value => {
  if (!value) return '';
  const kb = value / 1024;
  if (kb < 1024) return `${Math.round(kb)} KB · ${extensionLabel()}`;
  return `${(kb / 1024).toFixed(1)} MB · ${extensionLabel()}`;
};

const formatDate = value =>
  value ? new Date(value).toLocaleString('pt-BR') : '';

// The list loads one page at a time; the sentinel below the grid asks
// for the next page whenever it scrolls into view. Without this we were
// showing only the 60 most recent items — enough that on a busy account
// every visible row was from "hoje", giving the impression the hub only
// held today's media.
const fetchData = async ({ append = false } = {}) => {
  loading.value = true;
  error.value = null;
  try {
    const res = await axios.get(
      `/api/v1/accounts/${accountId.value}/media_hub`,
      {
        params: { type: activeTab.value, page: currentPage.value },
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
  videoErrors.value = new Set();
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

// The sentinel div sits at the very bottom of the list and triggers the
// next page when it scrolls into view. `rootMargin` fires the request
// ~400px before the user reaches the edge so the next batch is already
// in place when they get there.
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
watch(activeTab, resetAndFetch);

// "Ir para a mensagem" — jumps straight to the origin conversation.
// Uses the plain path (not a named route) because the inbox-scoped route
// requires an `inboxId` param we don't carry here. The `#message-X` hash
// is left in for future auto-scroll; the conversation view ignores it
// today, but every URL that eventually goes to that message has this
// same fragment.
const goToMessage = item => {
  if (!item.conversation_id) return;
  const hash = item.message_id ? `#message-${item.message_id}` : '';
  router.push(
    `/app/accounts/${accountId.value}/conversations/${item.conversation_id}${hash}`
  );
};

const openInNewTab = url => {
  if (!url) return;
  window.open(url, '_blank', 'noopener');
};

const copyToClipboard = value => {
  if (!value) return;
  navigator.clipboard?.writeText(value);
};

const close = () => {
  router.back();
};

// Contextual per-row menu — one is open at a time, tracked by item id.
const openMenuFor = ref(null);
const toggleMenu = id => {
  openMenuFor.value = openMenuFor.value === id ? null : id;
};
const closeMenu = () => {
  openMenuFor.value = null;
  sortMenuOpen.value = false;
};

// Multi-select — explicit mode toggled by the toolbar's check icon or
// by the "Selecionar" entry in a row's context menu. While it's off,
// checkboxes are hidden on every tab; while it's on, they render on
// every row and the bottom shelf is up so the operator can act in bulk.
const selectMode = ref(false);
const selectedIds = ref(new Set());

const isSelected = id => selectedIds.value.has(id);

const toggleSelect = id => {
  const next = new Set(selectedIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  selectedIds.value = next;
};

const enterSelectMode = id => {
  selectMode.value = true;
  toggleSelect(id);
};

const toggleSelectMode = () => {
  selectMode.value = !selectMode.value;
  if (!selectMode.value) selectedIds.value = new Set();
};

const clearSelection = () => {
  selectMode.value = false;
  selectedIds.value = new Set();
};

// Everything in view that the operator has ticked. Drives the count,
// size and enabled-state of the bulk-action buttons in the bar.
const selectedItems = computed(() =>
  items.value.filter(it => selectedIds.value.has(it.id))
);

const selectedSize = computed(() =>
  selectedItems.value.reduce((sum, it) => sum + (it.file_size || 0), 0)
);

// Human-readable file size — "731 KB" / "1.6 MB" like WhatsApp.
const humanSize = bytes => {
  if (!bytes) return null;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

// Reset selection whenever the operator flips to another tab — the
// bar's labels/actions differ between tabs and stray selections would
// confuse the totals.
watch(activeTab, () => clearSelection());

const showSelectionBar = computed(() => selectMode.value);

// Alias kept because the template already references it. Now that
// select-mode is explicit, both names return the same signal.
const forceCheckboxes = computed(() => selectMode.value);

// Toggle helpers for the toolbar's search / sort icons.
const toggleSearchMode = () => {
  searchMode.value = !searchMode.value;
  if (!searchMode.value) searchQuery.value = '';
};
const toggleSortMenu = () => {
  sortMenuOpen.value = !sortMenuOpen.value;
};

// Bulk actions — Baixar opens each URL on a new tab so the browser
// handles the concurrent download the same way it would if the operator
// clicked each row individually.
const bulkDownload = () => {
  selectedItems.value.forEach(item => {
    openInNewTab(item.file_url || item.url);
  });
};

// Apagar — hits the backend delete endpoint. Media / Document rows send
// attachment ids, Links send the parent message id (a link "row" is a
// URL mined out of a message's content, so removing the URL means
// dropping the message). Confirmation is required either way; a single
// row uses the context menu, multi-row uses the bottom shelf.
const deleteMediaHubItems = async rows => {
  if (!rows.length) return;
  const ids =
    activeTab.value === 'link'
      ? rows.map(i => i.message_id).filter(Boolean)
      : rows.map(i => i.id).filter(Boolean);
  if (!ids.length) return;
  try {
    await axios.delete(`/api/v1/accounts/${accountId.value}/media_hub`, {
      data: { type: activeTab.value, ids },
    });
    useAlert(t('MEDIA_HUB.DELETE.DONE'));
    clearSelection();
    fetchData();
  } catch (e) {
    useAlert(e.message || t('MEDIA_HUB.DELETE.FAILED'));
  }
};

const bulkDelete = () => {
  const count = selectedItems.value.length;
  if (!count) return;
  const message = t('MEDIA_HUB.DELETE.CONFIRM', { n: count });
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;
  deleteMediaHubItems(selectedItems.value);
};

const deleteOne = item => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('MEDIA_HUB.DELETE.CONFIRM_ONE'))) return;
  deleteMediaHubItems([item]);
};

// A click on the row body / thumbnail body always opens the target —
// the operator explicitly ticks the checkbox to select. This matches
// WhatsApp Business: clicking a photo previews it, clicking the box
// selects it. The two intents never bleed into each other.
const handleRowClick = item => {
  openInNewTab(activeTab.value === 'link' ? item.url : item.file_url);
};

const handleMediaClick = item => {
  openInNewTab(item.file_url);
};

// Same order as the WhatsApp Business media panel. Each tab only hides
// the items that don't make sense for its rows (Copiar on links only,
// Baixar off links); everything else stays put so muscle memory holds.
const menuItems = item => {
  const isLink = activeTab.value === 'link';
  const downloadUrl = item.file_url || item.url;
  return [
    {
      key: 'select',
      label: t('MEDIA_HUB.MENU.SELECT'),
      icon: 'i-lucide-square-check',
      action: () => enterSelectMode(item.id),
    },
    {
      key: 'open-link',
      label: t('MEDIA_HUB.MENU.OPEN_LINK_NEW_TAB'),
      icon: 'i-lucide-external-link',
      show: isLink,
      divider: true,
      action: () => openInNewTab(item.url),
    },
    {
      key: 'go-to-message',
      label: t('MEDIA_HUB.MENU.GO_TO_MESSAGE'),
      icon: 'i-lucide-message-square',
      divider: !isLink,
      action: () => goToMessage(item),
    },
    {
      key: 'download',
      label: t('MEDIA_HUB.MENU.DOWNLOAD'),
      icon: 'i-lucide-download',
      show: !isLink,
      action: () => openInNewTab(downloadUrl),
    },
    {
      key: 'copy',
      label: t('MEDIA_HUB.MENU.COPY'),
      icon: 'i-lucide-copy',
      show: isLink,
      action: () => copyToClipboard(item.url),
    },
    {
      key: 'delete',
      label: t('MEDIA_HUB.MENU.DELETE'),
      icon: 'i-lucide-trash-2',
      danger: true,
      divider: true,
      action: () => deleteOne(item),
    },
  ].filter(mi => mi.show === undefined || mi.show);
};

const runMenuAction = mi => {
  closeMenu();
  mi.action();
};
</script>

<template>
  <div class="w-full h-full overflow-hidden bg-n-slate-1" @click="closeMenu">
    <div class="mx-auto max-w-6xl h-full flex flex-col bg-n-solid-1 shadow-sm">
      <!-- Header -->
      <div
        class="grid grid-cols-[1fr_auto_1fr] items-end gap-3 border-b border-n-slate-4 px-6 pt-5"
      >
        <div>
          <h1 class="text-2xl font-semibold text-n-slate-12 leading-tight">
            {{ t('SIDEBAR.MEDIA') }}
          </h1>
          <p class="text-sm text-n-slate-11 mt-1 mb-4">
            {{ subtitle }}
          </p>
        </div>
        <nav v-if="!searchMode" class="flex gap-8 mb-[-1px]">
          <button
            v-for="tab in TABS"
            :key="tab.id"
            type="button"
            class="pb-3 pt-4 text-sm border-b-2 border-transparent text-n-slate-11 hover:text-n-slate-12"
            :class="{
              'border-n-slate-12 text-n-slate-12 font-semibold':
                activeTab === tab.id,
            }"
            @click="activeTab = tab.id"
          >
            {{ tab.label }}
          </button>
        </nav>
        <div v-else />
        <!-- Empty placeholder keeps the toolbar pinned to column 3.
             Without it, hiding the nav collapses the grid and the
             toolbar (auto-sized) drifts into the middle. -->
        <div class="flex justify-end items-center gap-1 pb-3 relative">
          <template v-if="selectMode">
            <button
              type="button"
              class="text-sm text-n-slate-12 hover:text-n-slate-11 px-3 py-1"
              @click="clearSelection"
            >
              {{ t('MEDIA_HUB.SELECTION.CANCEL') }}
            </button>
          </template>
          <template v-else>
            <div
              v-if="searchMode"
              class="flex items-center gap-2 px-3 py-0.5 rounded-full border-2 border-slate-900 w-96 max-w-full"
            >
              <span
                class="i-lucide-search size-3.5 text-n-slate-12 flex-shrink-0"
              />
              <input
                v-model="searchQuery"
                type="text"
                autofocus
                :placeholder="searchPlaceholder"
                class="!bg-transparent !border-0 !outline-0 !p-0 !m-0 !w-full !h-auto text-[11px] text-n-slate-12"
              />
            </div>
            <button
              v-if="!searchMode"
              type="button"
              class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('MEDIA_HUB.SEARCH.LABEL')"
              @click="toggleSearchMode"
            >
              <span class="i-lucide-search size-4" />
            </button>
            <button
              type="button"
              class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              :class="{ 'bg-n-alpha-2 text-n-slate-12': sortMenuOpen }"
              :title="t('MEDIA_HUB.SORT.LABEL')"
              @click.stop="toggleSortMenu"
            >
              <span class="i-lucide-align-left size-4 rotate-180" />
            </button>
            <button
              type="button"
              class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('MEDIA_HUB.MENU.SELECT')"
              @click="toggleSelectMode"
            >
              <span class="i-lucide-check-square size-4" />
            </button>
            <button
              type="button"
              class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('MEDIA_HUB.CLOSE')"
              @click="searchMode ? toggleSearchMode() : close()"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </template>
          <!-- Sort dropdown — anchored just below the sort icon. -->
          <div
            v-if="sortMenuOpen"
            class="absolute right-2 top-12 z-40 py-2 min-w-[220px] rounded-lg border border-n-slate-4 bg-n-solid-1 shadow-lg text-left"
            @click.stop
          >
            <p
              class="px-3 py-1 text-xs uppercase tracking-wide text-n-slate-11"
            >
              {{ t('MEDIA_HUB.SORT.SENDER') }}
            </p>
            <button
              v-for="opt in [
                { id: 'all', label: t('MEDIA_HUB.SORT.SENDER_ALL') },
                { id: 'me', label: t('MEDIA_HUB.SORT.SENDER_ME') },
                { id: 'others', label: t('MEDIA_HUB.SORT.SENDER_OTHERS') },
              ]"
              :key="opt.id"
              type="button"
              class="!p-0 flex items-center gap-3 w-full px-3 py-2 text-sm hover:bg-n-slate-2 text-n-slate-12"
              @click="senderFilter = opt.id"
            >
              <span
                class="w-4 h-4 rounded-full border-2 inline-flex items-center justify-center"
                :class="
                  senderFilter === opt.id
                    ? 'border-slate-900'
                    : 'border-slate-400'
                "
              >
                <span
                  v-if="senderFilter === opt.id"
                  class="w-2 h-2 rounded-full bg-slate-900"
                />
              </span>
              {{ opt.label }}
            </button>
            <div class="my-1 border-t border-n-slate-3" />
            <p
              class="px-3 py-1 text-xs uppercase tracking-wide text-n-slate-11"
            >
              {{ t('MEDIA_HUB.SORT.ORDER') }}
            </p>
            <button
              v-for="opt in [
                { id: 'newest', label: t('MEDIA_HUB.SORT.ORDER_NEWEST') },
                { id: 'oldest', label: t('MEDIA_HUB.SORT.ORDER_OLDEST') },
                { id: 'largest', label: t('MEDIA_HUB.SORT.ORDER_LARGEST') },
              ]"
              :key="opt.id"
              type="button"
              class="!p-0 flex items-center gap-3 w-full px-3 py-2 text-sm hover:bg-n-slate-2 text-n-slate-12"
              @click="sortOrder = opt.id"
            >
              <span
                class="w-4 h-4 rounded-full border-2 inline-flex items-center justify-center"
                :class="
                  sortOrder === opt.id ? 'border-slate-900' : 'border-slate-400'
                "
              >
                <span
                  v-if="sortOrder === opt.id"
                  class="w-2 h-2 rounded-full bg-slate-900"
                />
              </span>
              {{ opt.label }}
            </button>
          </div>
        </div>
      </div>

      <!-- Content -->
      <div class="flex-1 overflow-y-auto pl-6 pr-8 py-5">
        <p v-if="loading" class="text-sm text-n-slate-11">
          {{ t('MEDIA_HUB.LOADING') }}
        </p>
        <p v-else-if="error" class="text-sm text-n-ruby-9">
          {{ error }}
        </p>
        <p v-else-if="!items.length" class="py-16 text-center text-n-slate-11">
          {{ t('MEDIA_HUB.EMPTY') }}
        </p>

        <template v-else>
          <div
            v-for="group in groupedItems"
            :key="group.label"
            class="mb-8 last:mb-0"
          >
            <p class="text-base font-semibold text-n-slate-12 mb-1">
              {{ group.label }}
            </p>
            <p class="text-xs text-n-slate-11 mb-3">
              {{ group.rows.length }} {{ t('MEDIA_HUB.ITEMS_LABEL') }}
            </p>

            <!-- MEDIA GRID: rendered for image / video / audio tabs. Each
                 kind gets its own thumbnail treatment — a video tries the
                 browser's native first-frame poster and falls back to a
                 play icon; an audio always renders a sound-wave icon since
                 there's nothing rasterizable. -->
            <div
              v-if="isMediaGrid"
              class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-5 gap-1"
            >
              <div
                v-for="item in group.rows"
                :key="item.id"
                class="relative group"
              >
                <div
                  class="aspect-square bg-n-slate-3 overflow-hidden cursor-pointer"
                  @click.stop="handleMediaClick(item)"
                >
                  <img
                    v-if="
                      item.file_type === 'image' &&
                      (item.thumb_url || item.file_url)
                    "
                    :src="item.thumb_url || item.file_url"
                    :alt="item.fallback_title || ''"
                    loading="lazy"
                    class="w-full h-full object-cover"
                  />
                  <template v-else-if="item.file_type === 'video'">
                    <!-- The browser extracts the first frame natively when
                         it can decode the URL and CORS lets it through.
                         When it can't (a WhatsApp CDN URL is the usual
                         case), the `error` event flips the row to the
                         play-icon placeholder. -->
                    <video
                      v-if="item.file_url && !videoErrored(item.id)"
                      :src="item.file_url"
                      preload="metadata"
                      muted
                      playsinline
                      class="w-full h-full object-cover bg-n-slate-4"
                      @error="markVideoError(item.id)"
                    />
                    <div
                      v-else
                      class="w-full h-full flex items-center justify-center bg-n-slate-4 text-n-slate-11"
                    >
                      <span class="i-lucide-play-circle size-10" />
                    </div>
                  </template>
                  <div
                    v-else-if="item.file_type === 'audio'"
                    class="w-full h-full flex items-center justify-center bg-n-slate-4 text-n-slate-11"
                  >
                    <span class="i-lucide-audio-lines size-10" />
                  </div>
                  <span
                    v-if="item.file_type === 'video'"
                    class="absolute top-2 left-14 px-1.5 py-0.5 rounded text-[10px] bg-black/50 text-white"
                  >
                    {{ t('MEDIA_HUB.VIDEO') }}
                  </span>
                  <div
                    class="absolute inset-x-0 bottom-0 pt-6 pb-1.5 px-2 bg-gradient-to-t from-black/80 via-black/40 to-transparent"
                  >
                    <span
                      class="block text-[11px] font-semibold text-white truncate drop-shadow"
                    >
                      {{ item.sender_name }}
                    </span>
                  </div>
                </div>
                <!-- Multi-select checkbox — top-left. Never shows on
                     hover alone; only appears after the operator taps
                     "Selecionar" in the context menu (which flips
                     `forceCheckboxes` via the first tick) or when the
                     row is already selected. Matches WhatsApp Business.
                -->
                <button
                  v-if="forceCheckboxes || isSelected(item.id)"
                  type="button"
                  class="!p-0 absolute top-2 left-2 w-4 h-4 inline-flex items-center justify-center rounded-md shadow bg-white"
                  :class="{ 'ring-1 ring-slate-300': !isSelected(item.id) }"
                  :title="t('MEDIA_HUB.MENU.SELECT')"
                  @click.stop="toggleSelect(item.id)"
                >
                  <svg
                    v-if="isSelected(item.id)"
                    xmlns="http://www.w3.org/2000/svg"
                    class="size-3"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#111827"
                    stroke-width="3"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </button>
                <!-- Chevron overlay — top-right corner, visible on hover
                     or while the menu is open. Matches the WhatsApp
                     Business pattern. -->
                <!-- Chevron + menu share a small anchor at the top-right
                     corner of the thumbnail so the menu drops below the
                     arrow and grows rightward — even when that overflows
                     the current thumbnail into the next one. -->
                <div class="absolute top-2 right-2">
                  <button
                    type="button"
                    class="w-8 h-8 inline-flex items-center justify-center rounded-full bg-white/90 text-n-slate-11 shadow opacity-0 group-hover:opacity-100 transition-opacity"
                    :class="{ '!opacity-100': openMenuFor === item.id }"
                    :title="t('MEDIA_HUB.MENU.CONTEXT_MENU')"
                    @click.stop="toggleMenu(item.id)"
                  >
                    <span class="i-lucide-chevron-down size-4" />
                  </button>
                  <div
                    v-if="openMenuFor === item.id"
                    class="absolute top-full left-0 mt-1 z-30 py-1 min-w-[240px] rounded-lg border border-n-slate-4 bg-n-solid-1 shadow-lg text-left"
                    @click.stop
                  >
                    <template v-for="mi in menuItems(item)" :key="mi.key">
                      <div
                        v-if="mi.divider"
                        class="my-1 border-t border-n-slate-3"
                      />
                      <button
                        type="button"
                        class="flex items-center gap-3 w-full px-3 py-2 text-sm hover:bg-n-slate-2"
                        :class="
                          mi.danger ? 'text-n-ruby-11' : 'text-n-slate-12'
                        "
                        @click="runMenuAction(mi)"
                      >
                        <span
                          class="size-4"
                          :class="[
                            mi.icon,
                            mi.danger ? 'text-n-ruby-11' : 'text-n-slate-11',
                          ]"
                        />
                        {{ mi.label }}
                      </button>
                    </template>
                  </div>
                </div>
              </div>
            </div>

            <!-- DOCUMENTS / LINKS TABLE. `table-fixed` locks the columns
                 to the widths declared on the header so long URLs / names
                 truncate instead of forcing horizontal scroll on the
                 whole modal. -->
            <table v-else class="w-full text-sm table-fixed">
              <thead>
                <tr class="text-left text-n-slate-11 border-b border-n-slate-4">
                  <th v-if="forceCheckboxes" class="py-2 font-medium w-12" />
                  <th class="py-2 font-medium w-[34%]">
                    {{ activeTab === 'document' ? 'Documento' : 'Link' }}
                  </th>
                  <th class="py-2 font-medium w-[32%]">
                    {{ activeTab === 'document' ? 'Legenda' : 'Mensagem' }}
                  </th>
                  <th class="py-2 font-medium w-[22%]">
                    {{ t('MEDIA_HUB.SENT_BY') }}
                  </th>
                  <th class="py-2 w-[8%]" />
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="item in group.rows"
                  :key="item.id"
                  class="border-b border-n-slate-3 hover:bg-n-slate-2 align-top cursor-pointer"
                  :class="{ 'bg-slate-100': isSelected(item.id) }"
                  @click="handleRowClick(item)"
                >
                  <td
                    v-if="forceCheckboxes"
                    class="py-3 pl-3 pr-2 align-middle"
                  >
                    <button
                      type="button"
                      class="!p-0 inline-flex items-center justify-center w-4 h-4 rounded-md"
                      :class="
                        isSelected(item.id)
                          ? 'bg-slate-900'
                          : 'bg-transparent ring-2 ring-slate-400 hover:ring-slate-600'
                      "
                      :title="t('MEDIA_HUB.MENU.SELECT')"
                      @click.stop="toggleSelect(item.id)"
                    >
                      <svg
                        v-if="isSelected(item.id)"
                        xmlns="http://www.w3.org/2000/svg"
                        class="size-3"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="#ffffff"
                        stroke-width="3"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      >
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    </button>
                  </td>
                  <td class="py-3 pr-2">
                    <div class="flex items-center gap-3">
                      <span
                        v-if="activeTab === 'document'"
                        class="w-10 h-10 flex-shrink-0 rounded-lg inline-flex items-center justify-center text-[10px] font-bold bg-n-ruby-3 text-n-ruby-11"
                      >
                        {{
                          (item.extension || 'FILE').toUpperCase().slice(0, 4)
                        }}
                      </span>
                      <span
                        v-else
                        class="w-10 h-10 flex-shrink-0 rounded-lg inline-flex items-center justify-center bg-n-slate-3 text-n-slate-11"
                      >
                        <span class="i-lucide-link size-4" />
                      </span>
                      <div class="min-w-0 flex-1">
                        <div class="text-n-slate-12 truncate">
                          {{
                            activeTab === 'document'
                              ? item.fallback_title || 'Arquivo'
                              : item.url
                          }}
                        </div>
                        <div class="text-xs text-n-slate-11 mt-0.5">
                          {{
                            activeTab === 'document'
                              ? formatBytes(item.file_size)
                              : item.host
                          }}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td class="py-3 pr-2 text-n-slate-11">
                    <p class="line-clamp-2 break-words">
                      {{ item.caption || 'Sem legenda' }}
                    </p>
                  </td>
                  <td class="py-3 pr-2">
                    <div class="text-n-slate-12">
                      {{ item.sender_name }}
                    </div>
                    <div class="text-xs text-n-slate-11 mt-0.5">
                      {{ formatDate(item.created_at) }}
                    </div>
                  </td>
                  <td class="py-3 relative whitespace-nowrap">
                    <div class="flex items-center justify-end gap-1">
                      <button
                        type="button"
                        class="w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                        :title="
                          activeTab === 'document'
                            ? t('MEDIA_HUB.DOWNLOAD')
                            : t('MEDIA_HUB.OPEN')
                        "
                        @click.stop="
                          openInNewTab(
                            activeTab === 'document' ? item.file_url : item.url
                          )
                        "
                      >
                        <span
                          class="size-4"
                          :class="[
                            activeTab === 'document'
                              ? 'i-lucide-download'
                              : 'i-lucide-external-link',
                          ]"
                        />
                      </button>
                      <button
                        type="button"
                        class="w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                        :title="t('MEDIA_HUB.MORE')"
                        @click.stop="toggleMenu(item.id)"
                      >
                        <span class="i-lucide-chevron-down size-4" />
                      </button>
                    </div>
                    <div
                      v-if="openMenuFor === item.id"
                      class="absolute right-2 top-11 z-30 py-1 min-w-[240px] rounded-lg border border-n-slate-4 bg-n-solid-1 shadow-lg text-left"
                      @click.stop
                    >
                      <template v-for="mi in menuItems(item)" :key="mi.key">
                        <div
                          v-if="mi.divider"
                          class="my-1 border-t border-n-slate-3"
                        />
                        <button
                          type="button"
                          class="flex items-center gap-3 w-full px-3 py-2 text-sm hover:bg-n-slate-2"
                          :class="
                            mi.danger ? 'text-n-ruby-11' : 'text-n-slate-12'
                          "
                          @click="runMenuAction(mi)"
                        >
                          <span
                            class="size-4"
                            :class="[
                              mi.icon,
                              mi.danger ? 'text-n-ruby-11' : 'text-n-slate-11',
                            ]"
                          />
                          {{ mi.label }}
                        </button>
                      </template>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <!-- Infinite-scroll sentinel — sits below the last group and
               triggers a page bump whenever it comes into view. The
               observer honours `canLoadMore` so it goes idle once the
               last page has been fetched. -->
          <div ref="sentinel" class="h-4" />
          <p
            v-if="loading && items.length"
            class="py-4 text-center text-xs text-n-slate-11"
          >
            {{ t('MEDIA_HUB.LOADING') }}
          </p>
        </template>
      </div>

      <!-- Selection bar. Mirrors the WhatsApp Business bottom shelf:
           per-tab counts and size stats on the center, action pills to
           the right. The delete pill is red-tinted; the bar itself
           only mounts while the operator has anything selected. -->
      <div
        v-if="showSelectionBar"
        class="border-t border-n-slate-4 bg-n-solid-1 px-6 py-3 flex items-center gap-3"
        @click.stop
      >
        <button
          type="button"
          class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-sm font-medium bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4 disabled:opacity-40"
          :disabled="!selectedIds.size"
          :title="t('MEDIA_HUB.MENU.DELETE')"
          @click="bulkDelete"
        >
          <span class="i-lucide-trash-2 size-4" />
          <span v-if="selectedSize > 0">{{ humanSize(selectedSize) }}</span>
        </button>
        <div class="flex-1 text-center text-sm text-n-slate-11">
          <template v-if="selectedIds.size === 0">
            {{ t('MEDIA_HUB.SELECTION.EMPTY_SELECTED') }}
          </template>
          <template v-else-if="selectedIds.size === 1">
            {{ t('MEDIA_HUB.SELECTION.ONE_SELECTED') }}
          </template>
          <template v-else>
            {{
              t('MEDIA_HUB.SELECTION.MANY_SELECTED', { n: selectedIds.size })
            }}
          </template>
        </div>
        <button
          v-if="activeTab !== 'link'"
          type="button"
          class="w-9 h-9 inline-flex items-center justify-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-40"
          :disabled="!selectedIds.size"
          :title="t('MEDIA_HUB.MENU.DOWNLOAD')"
          @click="bulkDownload"
        >
          <span class="i-lucide-download size-4" />
        </button>
      </div>
    </div>
  </div>
</template>
