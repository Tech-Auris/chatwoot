<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

// Tabs mirror the mockup: image/video grid, docs table, links table.
const TABS = [
  { id: 'media', label: 'Mídias' },
  { id: 'document', label: 'Documentos' },
  { id: 'link', label: 'Links' },
];

const activeTab = ref('media');
const items = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const loading = ref(false);
const error = ref(null);

const subtitle = computed(() => {
  if (activeTab.value === 'media') return 'Mídias de todas as conversas';
  if (activeTab.value === 'document') return 'Documentos de todas as conversas';
  return 'Links de todas as conversas';
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

  items.value.forEach(item => {
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

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const res = await axios.get(
      `/api/v1/accounts/${accountId.value}/media_hub`,
      {
        params: { type: activeTab.value },
      }
    );
    items.value = res.data.items || [];
    meta.value = res.data.meta || meta.value;
  } catch (e) {
    error.value = e.message;
    items.value = [];
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);
watch(activeTab, fetchData);

const goToMessage = item => {
  if (!item.conversation_id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversationId: item.conversation_id,
    },
    hash: item.message_id ? `#message-${item.message_id}` : '',
  });
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
};

// Multi-select — the bottom shelf appears the moment there is anything
// ticked. Docs / Links show the checkbox all the time; the media grid
// only reveals it on hover unless something is already selected. The
// context menu's "Selecionar" seeds the first tick.
const selectedIds = ref(new Set());

const isSelected = id => selectedIds.value.has(id);

const toggleSelect = id => {
  const next = new Set(selectedIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  selectedIds.value = next;
};

const enterSelectMode = id => toggleSelect(id);

const clearSelection = () => {
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

const showSelectionBar = computed(() => selectedIds.value.size > 0);

// Media grid also needs to know when to force-show the checkbox — the
// bar is up (something's selected) OR the operator explicitly entered
// select-mode via the context menu, both cases collapse into "we have
// at least one selection".
const forceCheckboxes = computed(() => selectedIds.value.size > 0);

// Bulk actions — Baixar opens each URL on a new tab so the browser
// handles the concurrent download the same way it would if the operator
// clicked each row individually. Encaminhar / Favoritar / Apagar still
// route to the coming-soon toast; each needs its own endpoint and is
// tracked as a follow-up.
const bulkDownload = () => {
  selectedItems.value.forEach(item => {
    openInNewTab(item.file_url || item.url);
  });
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

// Actions that need dedicated endpoints / UX flows (multi-select, forward,
// favorites, delete) surface as toast placeholders for now so the menu
// shape matches the WhatsApp Business reference. Each has a follow-up PR
// planned; the toast is what the operator sees until then.
const showComingSoon = () => useAlert(t('MEDIA_HUB.COMING_SOON'));

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
      key: 'reply',
      label: t('MEDIA_HUB.MENU.REPLY'),
      icon: 'i-lucide-corner-up-left',
      // For now the reply intent lands the operator on the message; the
      // ReplyBox itself is where they pick up. Focus-on-quote is a v2.
      action: () => goToMessage(item),
    },
    {
      key: 'reply-private',
      label: t('MEDIA_HUB.MENU.REPLY_PRIVATE'),
      icon: 'i-lucide-user-round',
      // Group private reply — not exposed in our conversation UI yet, so
      // the entry sits behind the same "coming soon" toast until we ship
      // the private-reply intent on the ReplyBox.
      action: showComingSoon,
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
      key: 'forward',
      label: t('MEDIA_HUB.MENU.FORWARD'),
      icon: 'i-lucide-forward',
      action: showComingSoon,
    },
    {
      key: 'favorite',
      label: t('MEDIA_HUB.MENU.FAVORITE'),
      icon: 'i-lucide-star',
      action: showComingSoon,
    },
    {
      key: 'delete',
      label: t('MEDIA_HUB.MENU.DELETE'),
      icon: 'i-lucide-trash-2',
      danger: true,
      divider: true,
      action: showComingSoon,
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
        class="grid grid-cols-[1fr_auto_1fr] items-end border-b border-n-slate-4 px-6 pt-5"
      >
        <div>
          <h1 class="text-2xl font-semibold text-n-slate-12 leading-tight">
            {{ t('SIDEBAR.MEDIA') }}
          </h1>
          <p class="text-sm text-n-slate-11 mt-1 mb-4">
            {{ subtitle }}
          </p>
        </div>
        <nav class="flex gap-8 mb-[-1px]">
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
        <div class="flex justify-end items-center gap-2 pb-3">
          <button
            v-if="showSelectionBar"
            type="button"
            class="text-sm text-n-slate-12 hover:text-n-slate-11 px-2 py-1"
            @click="clearSelection"
          >
            {{ t('MEDIA_HUB.SELECTION.CANCEL') }}
          </button>
          <button
            v-else
            type="button"
            class="w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :title="t('MEDIA_HUB.CLOSE')"
            @click="close"
          >
            <span class="i-lucide-x size-4" />
          </button>
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

            <!-- MEDIA GRID -->
            <div
              v-if="activeTab === 'media'"
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
                    v-if="item.thumb_url || item.file_url"
                    :src="item.thumb_url || item.file_url"
                    :alt="item.fallback_title || ''"
                    loading="lazy"
                    class="w-full h-full object-cover"
                  />
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
                  class="absolute top-2 left-2 w-6 h-6 inline-flex items-center justify-center rounded-lg shadow bg-white"
                  :class="{ 'ring-1 ring-slate-300': !isSelected(item.id) }"
                  :title="t('MEDIA_HUB.MENU.SELECT')"
                  @click.stop="toggleSelect(item.id)"
                >
                  <svg
                    v-if="isSelected(item.id)"
                    xmlns="http://www.w3.org/2000/svg"
                    width="14"
                    height="14"
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
                <button
                  type="button"
                  class="absolute top-2 right-2 w-8 h-8 inline-flex items-center justify-center rounded-full bg-white/90 text-n-slate-11 shadow opacity-0 group-hover:opacity-100 transition-opacity"
                  :class="{ '!opacity-100': openMenuFor === item.id }"
                  :title="t('MEDIA_HUB.MENU.CONTEXT_MENU')"
                  @click.stop="toggleMenu(item.id)"
                >
                  <span class="i-lucide-chevron-down size-4" />
                </button>
                <div
                  v-if="openMenuFor === item.id"
                  class="absolute top-12 right-2 z-30 py-1 min-w-[240px] rounded-lg border border-n-slate-4 bg-n-solid-1 shadow-lg text-left"
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
                      :class="mi.danger ? 'text-n-ruby-11' : 'text-n-slate-12'"
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

            <!-- DOCUMENTS / LINKS TABLE. `table-fixed` locks the columns
                 to the widths declared on the header so long URLs / names
                 truncate instead of forcing horizontal scroll on the
                 whole modal. -->
            <table v-else class="w-full text-sm table-fixed">
              <thead>
                <tr class="text-left text-n-slate-11 border-b border-n-slate-4">
                  <th class="py-2 font-medium w-12" />
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
                  <td class="py-3 pl-3 pr-2 align-middle">
                    <button
                      type="button"
                      class="inline-flex items-center justify-center w-6 h-6 rounded-lg"
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
                        width="14"
                        height="14"
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
          @click="showComingSoon"
        >
          <span class="i-lucide-trash-2 size-4" />
          <span v-if="selectedSize > 0">{{ humanSize(selectedSize) }}</span>
        </button>
        <div class="flex-1 text-center text-sm text-n-slate-11">
          {{
            selectedIds.size === 1
              ? t('MEDIA_HUB.SELECTION.ONE_SELECTED')
              : t('MEDIA_HUB.SELECTION.MANY_SELECTED', { n: selectedIds.size })
          }}
        </div>
        <button
          type="button"
          class="w-9 h-9 inline-flex items-center justify-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-40"
          :disabled="!selectedIds.size"
          :title="t('MEDIA_HUB.MENU.FAVORITE')"
          @click="showComingSoon"
        >
          <span class="i-lucide-star size-4" />
        </button>
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
        <button
          type="button"
          class="w-10 h-10 inline-flex items-center justify-center rounded-full bg-n-slate-12 text-white hover:bg-n-slate-11 disabled:opacity-40"
          :disabled="!selectedIds.size"
          :title="t('MEDIA_HUB.MENU.FORWARD')"
          @click="showComingSoon"
        >
          <span class="i-lucide-forward size-4" />
        </button>
      </div>
    </div>
  </div>
</template>
