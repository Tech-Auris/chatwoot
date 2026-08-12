<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'shared/components/Spinner.vue';
import StatusBadge from './components/StatusBadge.vue';
import TemplateDetailDrawer from './components/TemplateDetailDrawer.vue';

import MetaTemplatesAPI from 'dashboard/api/metaTemplates';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

// Only manager and administrator can create templates on Meta. Agents
// stay on the read-only view — matches MetaTemplatePolicy#create?.
const currentRole = useMapGetter('getCurrentRole');
const canCreateTemplate = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

// Cloud WhatsApp inbox universe. Comes from the already-hydrated
// inboxes store — if a user reaches this page directly without inboxes
// loaded (deep link), we dispatch once on mount.
const inboxes = useMapGetter('inboxes/getInboxes');
const cloudInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const selectedInboxId = ref(null);
const templates = ref([]);
const lastSyncedAt = ref(null);
// Start in loading so the initial paint (before we know whether
// inboxes are populated) shows a spinner rather than briefly flashing
// the "no Cloud inbox" empty state — which was persisting on hard
// refreshes where inboxes hadn't been fetched yet.
const loading = ref(true);
const syncing = ref(false);
// Tracks whether the inbox store has been resolved at least once in this
// session. Without this we cannot tell "no Cloud inbox exists" apart
// from "inbox store hasn't been fetched yet"; the empty state used to
// render immediately on mount with `cloudInboxes.length === 0` and
// stayed stuck if the store fetch happened later or failed silently.
const inboxesResolved = ref(inboxes.value.length > 0);
const search = ref('');
const statusFilter = ref('ALL');
const categoryFilter = ref('ALL');
const selectedTemplate = ref(null);
const drawerOpen = ref(false);

const STATUS_OPTIONS = [
  'ALL',
  'APPROVED',
  'PENDING',
  'REJECTED',
  'PAUSED',
  'DISABLED',
  'IN_APPEAL',
];
const CATEGORY_OPTIONS = ['ALL', 'MARKETING', 'UTILITY', 'AUTHENTICATION'];

// Client-side filter chain: status → category → free-text search on
// name. The API returns everything in one go so all filtering stays
// local — Meta template catalogs are small enough (dozens, not
// thousands) that this is fine.
const filteredTemplates = computed(() => {
  let list = templates.value;

  if (statusFilter.value !== 'ALL') {
    list = list.filter(
      t2 => (t2.status || '').toUpperCase() === statusFilter.value
    );
  }
  if (categoryFilter.value !== 'ALL') {
    list = list.filter(
      t2 => (t2.category || '').toUpperCase() === categoryFilter.value
    );
  }
  if (search.value.trim()) {
    list = picoSearch(list, search.value.trim(), ['name', 'language']);
  }
  return list;
});

// Once per inbox per session we auto-fire a sync when the local cache
// looks stale enough that the operator would land on an empty page
// (never synced, or last sync older than 24h). The 5-min background
// scheduler still handles fresh-enough inboxes; this only saves the
// operator from watching an empty screen and clicking Sincronizar
// themselves. Set-based so re-selecting the same inbox on the same
// session doesn't retrigger — filters, drawer opens, etc. leave this
// alone.
const AUTO_SYNC_STALE_MS = 24 * 60 * 60 * 1000;
const autoSyncedInboxes = ref(new Set());

const shouldAutoSync = () => {
  if (templates.value.length > 0) return false;
  if (autoSyncedInboxes.value.has(selectedInboxId.value)) return false;
  if (!lastSyncedAt.value) return true;
  const lastSyncMs = new Date(lastSyncedAt.value).getTime();
  if (Number.isNaN(lastSyncMs)) return true;
  return Date.now() - lastSyncMs > AUTO_SYNC_STALE_MS;
};

const runSync = async ({ silent = false } = {}) => {
  if (!selectedInboxId.value || syncing.value) return;
  syncing.value = true;
  try {
    const { data } = await MetaTemplatesAPI.sync({
      inboxId: selectedInboxId.value,
    });
    templates.value = data.templates || [];
    lastSyncedAt.value = data.last_synced_at;
    if (!silent) useAlert(t('META_TEMPLATES.SYNC.SUCCESS'));
  } catch (err) {
    // Auto-sync stays quiet on failure too — the 5-min background scheduler
    // will retry, and the user can still hit Sincronizar to see the error.
    if (!silent) {
      useAlert(err?.response?.data?.error || t('META_TEMPLATES.SYNC.FAILED'));
    }
  } finally {
    syncing.value = false;
  }
};

const fetchTemplates = async () => {
  if (!selectedInboxId.value) return;
  loading.value = true;
  try {
    const { data } = await MetaTemplatesAPI.fetch({
      inboxId: selectedInboxId.value,
    });
    templates.value = data.templates || [];
    lastSyncedAt.value = data.last_synced_at;
  } catch (err) {
    useAlert(
      err?.response?.data?.error || t('META_TEMPLATES.ERRORS.FETCH_FAILED')
    );
    templates.value = [];
  } finally {
    loading.value = false;
  }

  if (shouldAutoSync()) {
    autoSyncedInboxes.value.add(selectedInboxId.value);
    await runSync({ silent: true });
  }
};

const openDetail = template => {
  selectedTemplate.value = template;
  drawerOpen.value = true;
};

const closeDetail = () => {
  drawerOpen.value = false;
  selectedTemplate.value = null;
};

// Edit flow: drawer emits `edit` → we push to the edit route with the
// selected inbox in the query so the edit page knows which cache to
// resolve the template against.
const editTemplate = template => {
  closeDetail();
  router.push({
    name: 'meta_templates_edit',
    params: { id: template.id },
    query: { inbox_id: selectedInboxId.value },
  });
};

// Delete flow: drawer emits `delete` → we cache the target and open a
// confirm dialog. The dialog's `confirm` calls the API, refreshes the
// cached list from the response, and closes both surfaces.
const deleteDialogRef = ref(null);
const templateToDelete = ref(null);
const deleting = ref(false);

const requestDelete = template => {
  templateToDelete.value = template;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  if (!templateToDelete.value || deleting.value) return;
  deleting.value = true;
  try {
    const { data } = await MetaTemplatesAPI.delete({
      inboxId: selectedInboxId.value,
      templateId: templateToDelete.value.id,
    });
    templates.value = data.templates || [];
    lastSyncedAt.value = data.last_synced_at;
    useAlert(t('META_TEMPLATES.DELETE.SUCCESS'));
    closeDetail();
    templateToDelete.value = null;
  } catch (err) {
    const data = err?.response?.data || {};
    const details = data.details ? ` (${data.details})` : '';
    useAlert((data.error || t('META_TEMPLATES.DELETE.FAILED')) + details);
  } finally {
    deleting.value = false;
    deleteDialogRef.value?.close();
  }
};

const formatDate = iso => {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleString();
  } catch (_e) {
    return iso;
  }
};

// Auto-select the first Cloud inbox when the list resolves. If the user
// only has one, they never see the dropdown as a "picker" — it just
// stays there as a label. When cloudInboxes is empty (should not happen
// because the sidebar gate hides the menu, but handles the race where
// inboxes are still loading), the empty state below takes over.
watch(
  cloudInboxes,
  next => {
    if (!selectedInboxId.value && next.length > 0) {
      selectedInboxId.value = next[0].id;
    }
  },
  { immediate: true }
);

// The sidebar (or any other page mounted before us) may have already
// hydrated the inbox store — treat that as "resolved" too, so we don't
// wait on the onMounted dispatch just to flip the flag.
watch(
  () => inboxes.value.length,
  count => {
    if (count > 0) inboxesResolved.value = true;
  },
  { immediate: true }
);

watch(selectedInboxId, () => {
  templates.value = [];
  lastSyncedAt.value = null;
  fetchTemplates();
});

onMounted(async () => {
  if (!inboxes.value.length) {
    try {
      await store.dispatch('inboxes/get');
    } finally {
      inboxesResolved.value = true;
      // If the store fetch resolved with no inboxes at all, stop the
      // initial loading spinner — otherwise fetchTemplates never fires
      // (no selectedInboxId) and the operator stares at a spinner
      // forever. The `no-records-found` branch takes over from here.
      if (!inboxes.value.length) loading.value = false;
    }
  }
});
</script>

<template>
  <SettingsLayout
    :no-records-found="inboxesResolved && cloudInboxes.length === 0"
    :no-records-message="t('META_TEMPLATES.EMPTY.NO_CLOUD_INBOX')"
    :is-loading="loading && templates.length === 0"
    :loading-message="t('META_TEMPLATES.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('META_TEMPLATES.HEADER.TITLE')"
        :description="t('META_TEMPLATES.HEADER.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="grid gap-4">
        <!-- Filter row: match the styling used across settings/reports so
             every field (selects and search input) sits on the same
             baseline. Native selects get the same outline/rounded-lg/
             bg-alpha treatment the design system uses elsewhere. -->
        <div class="flex flex-wrap items-end gap-3 justify-between">
          <div class="flex flex-wrap items-end gap-3">
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.INBOX') }}
              <select
                v-model="selectedInboxId"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand min-w-64"
              >
                <option
                  v-for="inbox in cloudInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.STATUS') }}
              <select
                v-model="statusFilter"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand min-w-40"
              >
                <option v-for="s in STATUS_OPTIONS" :key="s" :value="s">
                  {{ t(`META_TEMPLATES.STATUS.${s}`, s) }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.CATEGORY') }}
              <select
                v-model="categoryFilter"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 h-10 text-sm text-n-slate-12 focus:outline-n-brand min-w-44"
              >
                <option v-for="c in CATEGORY_OPTIONS" :key="c" :value="c">
                  {{ t(`META_TEMPLATES.CATEGORY.${c}`, c) }}
                </option>
              </select>
            </label>
            <!-- Native input with the exact same class shape used on the
                 three selects. The Chatwoot `<Input>` component wraps
                 itself in an extra flex container that adds spacing and
                 pushes the field below the row baseline; the raw `<input>`
                 with identical classes lines up pixel-for-pixel. -->
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.FILTERS.SEARCH') }}
              <input
                v-model="search"
                type="text"
                class="bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 h-10 text-sm text-n-slate-12 focus:outline-n-brand placeholder:text-n-slate-10 min-w-64"
                :placeholder="t('META_TEMPLATES.FILTERS.SEARCH_PLACEHOLDER')"
              />
            </label>
          </div>
          <div class="flex items-center gap-2">
            <span v-if="lastSyncedAt" class="text-xs text-n-slate-11">
              {{ t('META_TEMPLATES.LAST_SYNCED') }}
              {{ formatDate(lastSyncedAt) }}
            </span>
            <Button
              sm
              faded
              slate
              :disabled="syncing || !selectedInboxId"
              @click="() => runSync()"
            >
              <Spinner v-if="syncing" class="!w-4 !h-4 !p-0" />
              <span v-else>{{ t('META_TEMPLATES.SYNC.BUTTON') }}</span>
            </Button>
            <Button
              v-if="canCreateTemplate"
              sm
              solid
              blue
              :label="t('META_TEMPLATES.NEW.CTA')"
              @click="$router.push({ name: 'meta_templates_new' })"
            />
          </div>
        </div>

        <!-- Table -->
        <div
          v-if="!loading && filteredTemplates.length === 0"
          class="py-12 text-center text-n-slate-11"
        >
          {{
            templates.length === 0
              ? t('META_TEMPLATES.EMPTY.NO_TEMPLATES')
              : t('META_TEMPLATES.EMPTY.NO_MATCH')
          }}
        </div>

        <div v-else class="border border-n-weak rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-n-alpha-1 text-n-slate-11 text-xs">
              <tr>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.NAME') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.CATEGORY') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.LANGUAGE') }}
                </th>
                <th class="text-left px-4 py-2 font-medium">
                  {{ t('META_TEMPLATES.TABLE.STATUS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="template in filteredTemplates"
                :key="`${template.id || template.name}-${template.language}`"
                class="hover:bg-n-alpha-1 cursor-pointer text-n-slate-12"
                @click="openDetail(template)"
              >
                <td class="px-4 py-3 font-medium">
                  {{ template.name }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ template.category }}
                </td>
                <td class="px-4 py-3 text-n-slate-11">
                  {{ template.language }}
                </td>
                <td class="px-4 py-3">
                  <StatusBadge :status="template.status" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <TemplateDetailDrawer
        :template="selectedTemplate"
        :inbox-id="selectedInboxId"
        :open="drawerOpen"
        :deleting="deleting"
        @close="closeDetail"
        @delete="requestDelete"
        @edit="editTemplate"
      />

      <Dialog
        ref="deleteDialogRef"
        type="alert"
        :title="t('META_TEMPLATES.DELETE.TITLE')"
        :description="
          templateToDelete
            ? t('META_TEMPLATES.DELETE.DESCRIPTION', {
                name: templateToDelete.name,
              })
            : ''
        "
        :confirm-button-label="t('META_TEMPLATES.DELETE.CONFIRM')"
        :is-loading="deleting"
        :disable-confirm-button="deleting"
        @confirm="confirmDelete"
      />
    </template>
  </SettingsLayout>
</template>
