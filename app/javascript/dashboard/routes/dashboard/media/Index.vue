<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import axios from 'axios';
import { useMapGetter } from 'dashboard/composables/store';
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

// Bucket everything into human-friendly date groups so the layout matches
// the WhatsApp Business reference the operator already knows.
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
  const startOfThisWeek = new Date(today);
  startOfThisWeek.setDate(today.getDate() - today.getDay());
  const startOfLastWeek = new Date(startOfThisWeek);
  startOfLastWeek.setDate(startOfThisWeek.getDate() - 7);

  const bucketFor = date => {
    const d = startOfDay(date);
    if (d.getTime() === today.getTime()) return 'Hoje';
    if (d.getTime() === yesterday.getTime()) return 'Ontem';
    if (d >= startOfThisWeek) return 'Esta semana';
    if (d >= startOfLastWeek) return 'Semana passada';
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
        <div class="flex justify-end gap-1 pb-3">
          <button
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
      <div class="flex-1 overflow-y-auto px-6 py-5">
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
                class="relative aspect-square bg-n-slate-3 overflow-hidden group cursor-pointer"
                @click="openInNewTab(item.file_url)"
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
                  class="absolute top-2 left-2 px-1.5 py-0.5 rounded text-[10px] bg-black/50 text-white"
                >
                  {{ t('MEDIA_HUB.VIDEO') }}
                </span>
                <span
                  class="absolute bottom-0 left-0 right-0 px-2 py-1 text-[11px] text-white bg-gradient-to-t from-black/55 to-transparent truncate"
                >
                  {{ item.sender_name }}
                </span>
              </div>
            </div>

            <!-- DOCUMENTS / LINKS TABLE -->
            <table v-else class="w-full text-sm">
              <thead>
                <tr class="text-left text-n-slate-11 border-b border-n-slate-4">
                  <th class="py-2 font-medium">
                    {{ activeTab === 'document' ? 'Documento' : 'Link' }}
                  </th>
                  <th class="py-2 font-medium">
                    {{ activeTab === 'document' ? 'Legenda' : 'Mensagem' }}
                  </th>
                  <th class="py-2 font-medium">
                    {{ t('MEDIA_HUB.SENT_BY') }}
                  </th>
                  <th class="py-2 w-16" />
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="item in group.rows"
                  :key="item.id"
                  class="border-b border-n-slate-3 hover:bg-n-slate-2 align-top"
                >
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
                      <div class="min-w-0">
                        <div class="text-n-slate-12 truncate max-w-md">
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
                    <p class="line-clamp-2 max-w-md">
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
                  <td class="py-3 text-right relative">
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
                    <div
                      v-if="openMenuFor === item.id"
                      class="absolute right-2 top-11 z-10 py-1 min-w-[220px] rounded-lg border border-n-slate-4 bg-n-solid-1 shadow-lg text-left"
                      @click.stop
                    >
                      <button
                        v-if="activeTab === 'link'"
                        type="button"
                        class="flex items-center gap-2 w-full px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-slate-2"
                        @click="
                          openInNewTab(item.url);
                          closeMenu();
                        "
                      >
                        <span
                          class="i-lucide-external-link size-4 text-n-slate-11"
                        />
                        {{ t('MEDIA_HUB.OPEN_LINK_NEW_TAB') }}
                      </button>
                      <button
                        type="button"
                        class="flex items-center gap-2 w-full px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-slate-2"
                        @click="
                          goToMessage(item);
                          closeMenu();
                        "
                      >
                        <span
                          class="i-lucide-message-square size-4 text-n-slate-11"
                        />
                        {{ t('MEDIA_HUB.GO_TO_MESSAGE') }}
                      </button>
                      <button
                        type="button"
                        class="flex items-center gap-2 w-full px-3 py-1.5 text-sm text-n-slate-12 hover:bg-n-slate-2"
                        @click="
                          copyToClipboard(
                            activeTab === 'link'
                              ? item.url
                              : item.fallback_title
                          );
                          closeMenu();
                        "
                      >
                        <span class="i-lucide-copy size-4 text-n-slate-11" />
                        {{ t('MEDIA_HUB.COPY') }}
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
