<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import format from 'date-fns/format';
import AudiencesAPI from 'dashboard/api/audiences';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ImportAudienceDialog from './components/ImportAudienceDialog.vue';
import { useAudienceFields } from './useAudienceFields';

// Marketing → Públicos: the account's saved audiences, with the rule that
// feeds each one, its window and its size now.
const { t } = useI18n();
const router = useRouter();
const { describe, describeWindow, timeAgo } = useAudienceFields();

const audiences = ref([]);
const meta = ref({});
const kind = ref('');
const isLoading = ref(true);
const hasError = ref(false);
const importDialogRef = ref(null);

const kindFilters = computed(() => [
  { value: '', label: t('AUDIENCES.FILTER.ALL') },
  { value: 'dynamic', label: t('AUDIENCES.FILTER.DYNAMIC') },
  { value: 'static', label: t('AUDIENCES.FILTER.STATIC') },
]);

const fetchAudiences = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await AudiencesAPI.list({ kind: kind.value || undefined });
    audiences.value = data.payload;
    meta.value = data.meta;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const pickKind = value => {
  kind.value = value;
  fetchAudiences();
};

const kindLabel = value => t(`AUDIENCES.KIND.${value.toUpperCase()}`);
const createdBy = audience =>
  t('AUDIENCES.TABLE.CREATED_BY', {
    name: audience.created_by?.name || '—',
    date: format(new Date(audience.created_at * 1000), 'dd/MM'),
  });
const updatedAt = audience =>
  timeAgo(audience.counted_at || audience.created_at);
const lastDownload = computed(() =>
  meta.value.last_download_at
    ? t('AUDIENCES.STATS.LAST_DOWNLOAD', {
        date: format(
          new Date(meta.value.last_download_at * 1000),
          'dd/MM HH:mm'
        ),
      })
    : t('AUDIENCES.STATS.NO_DOWNLOAD')
);

const open = audience =>
  router.push({
    name: 'marketing_audiences_show',
    params: { audienceId: audience.id },
  });

onMounted(fetchAudiences);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <header class="flex flex-wrap items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="mb-1 text-heading-1 text-n-slate-12">
            {{ t('AUDIENCES.HEADER') }}
          </h1>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('AUDIENCES.DESCRIPTION') }}
          </p>
        </div>
        <div class="flex gap-2">
          <Button
            :label="t('AUDIENCES.IMPORT')"
            icon="i-lucide-upload"
            variant="faded"
            color="slate"
            size="sm"
            @click="importDialogRef?.open()"
          />
          <Button
            :label="t('AUDIENCES.NEW')"
            icon="i-lucide-plus"
            size="sm"
            @click="router.push({ name: 'marketing_audiences_new' })"
          />
        </div>
      </header>

      <div class="grid grid-cols-1 gap-3 mb-6 md:grid-cols-3">
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
          <p class="mb-1 text-xs text-n-slate-11">
            {{ t('AUDIENCES.STATS.ACTIVE') }}
          </p>
          <p class="mb-0 text-2xl font-semibold text-n-slate-12">
            {{ meta.total_count ?? '—' }}
          </p>
        </div>
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
          <p class="mb-1 text-xs text-n-slate-11">
            {{ t('AUDIENCES.STATS.DOWNLOADS') }}
          </p>
          <p class="mb-0 text-2xl font-semibold text-n-slate-12">
            {{ meta.downloads_last_30_days ?? '—' }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">{{ lastDownload }}</p>
        </div>
        <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
          <p class="mb-1 text-xs text-n-slate-11">
            {{ t('AUDIENCES.STATS.CAMPAIGNS') }}
          </p>
          <p class="mb-0 text-2xl font-semibold text-n-slate-12">
            {{ meta.campaigns_last_30_days ?? '—' }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('AUDIENCES.STATS.CAMPAIGNS_HINT') }}
          </p>
        </div>
      </div>

      <div class="flex gap-2 mb-3">
        <Button
          v-for="filter in kindFilters"
          :key="filter.value"
          :label="filter.label"
          size="sm"
          :variant="kind === filter.value ? 'solid' : 'faded'"
          :color="kind === filter.value ? 'blue' : 'slate'"
          @click="pickKind(filter.value)"
        />
      </div>

      <div v-if="isLoading" class="flex justify-center py-10">
        <Spinner />
      </div>
      <p v-else-if="hasError" class="py-10 text-sm text-center text-n-ruby-11">
        {{ t('AUDIENCES.LOAD_ERROR') }}
      </p>
      <div
        v-else-if="!audiences.length"
        class="flex flex-col items-center gap-1 py-12 text-center"
      >
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('AUDIENCES.EMPTY.TITLE') }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('AUDIENCES.EMPTY.SUBTITLE') }}
        </p>
      </div>
      <div v-else class="overflow-x-auto border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead>
            <tr
              class="text-xs text-left border-b text-n-slate-11 border-n-weak"
            >
              <th class="px-4 py-2 font-medium">
                {{ t('AUDIENCES.TABLE.NAME') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ t('AUDIENCES.TABLE.KIND') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ t('AUDIENCES.TABLE.RULE') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ t('AUDIENCES.TABLE.WINDOW') }}
              </th>
              <th class="px-4 py-2 font-medium text-right">
                {{ t('AUDIENCES.TABLE.CONTACTS') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ t('AUDIENCES.TABLE.UPDATED') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="audience in audiences"
              :key="audience.id"
              class="border-b cursor-pointer border-n-weak last:border-b-0 hover:bg-n-alpha-1"
              @click="open(audience)"
            >
              <td class="px-4 py-3">
                <p class="mb-0 font-medium text-n-slate-12">
                  {{ audience.name }}
                </p>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ createdBy(audience) }}
                </p>
              </td>
              <td class="px-4 py-3 whitespace-nowrap">
                <span
                  class="px-2 py-0.5 text-xs rounded-md"
                  :class="
                    audience.kind === 'dynamic'
                      ? 'bg-n-blue-3 text-n-blue-11'
                      : 'bg-n-alpha-2 text-n-slate-11'
                  "
                >
                  {{ kindLabel(audience.kind) }}
                </span>
              </td>
              <td class="px-4 py-3">
                <div class="flex flex-wrap gap-1">
                  <template v-if="audience.kind === 'static'">
                    <span class="text-xs text-n-slate-11">
                      {{ t('AUDIENCES.RULE.FIXED_LIST') }}
                    </span>
                  </template>
                  <template v-else>
                    <span
                      v-for="(condition, index) in audience.rule"
                      :key="`r${index}`"
                      class="px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
                    >
                      {{ describe(condition) }}
                    </span>
                    <span
                      v-if="!audience.rule.length"
                      class="text-xs text-n-slate-11"
                    >
                      {{ t('AUDIENCES.RULE.EVERYONE') }}
                    </span>
                    <span
                      v-for="(condition, index) in audience.exclusion"
                      :key="`e${index}`"
                      class="px-2 py-0.5 text-xs rounded-md bg-n-ruby-3 text-n-ruby-11"
                    >
                      {{ t('AUDIENCES.RULE.EXCEPT') }} {{ describe(condition) }}
                    </span>
                  </template>
                </div>
              </td>
              <td class="px-4 py-3 text-xs whitespace-nowrap text-n-slate-11">
                {{
                  audience.kind === 'dynamic'
                    ? describeWindow(audience.window)
                    : '—'
                }}
              </td>
              <td class="px-4 py-3 font-medium text-right text-n-slate-12">
                {{ audience.contacts_count.toLocaleString() }}
              </td>
              <td class="px-4 py-3 text-xs whitespace-nowrap text-n-slate-11">
                {{ updatedAt(audience) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-3 text-xs text-n-slate-11">
        {{ t('AUDIENCES.FOOTNOTE') }}
      </p>
    </div>
    <ImportAudienceDialog ref="importDialogRef" />
  </section>
</template>
