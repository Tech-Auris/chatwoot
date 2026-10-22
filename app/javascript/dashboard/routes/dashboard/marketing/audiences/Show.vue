<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import format from 'date-fns/format';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAlert } from 'dashboard/composables';
import AudiencesAPI from 'dashboard/api/audiences';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import AddContactsDialog from './components/AddContactsDialog.vue';
import { useAudienceFields } from './useAudienceFields';

// An audience opened: who is in it now, the rule that feeds it (dynamic) or
// the fixed list (static), and what was done with it ("Ações").
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { describe, describeWindow } = useAudienceFields();

const audienceId = computed(() => route.params.audienceId);
const audience = ref(null);
const contacts = ref([]);
const contactsMeta = ref({ current_page: 1, total_count: 0 });
const isLoading = ref(true);
const snapshotDialogRef = ref(null);
const deleteDialogRef = ref(null);
const addContactsDialogRef = ref(null);
const snapshotName = ref('');
const isWorking = ref(false);

const PER_PAGE = 25;
const isDynamic = computed(() => audience.value?.kind === 'dynamic');
const events = computed(() => audience.value?.events || []);
const recentDownloads = computed(() => {
  const since = Date.now() / 1000 - 30 * 24 * 3600;
  return events.value.filter(e => e.kind === 'download' && e.created_at > since)
    .length;
});

const fetchContacts = async (page = 1) => {
  const { data } = await AudiencesAPI.contacts(audienceId.value, page);
  contacts.value = data.payload;
  contactsMeta.value = data.meta;
};

const fetchAudience = async () => {
  isLoading.value = true;
  try {
    const { data } = await AudiencesAPI.show(audienceId.value);
    audience.value = data.payload;
    await fetchContacts(1);
  } finally {
    isLoading.value = false;
  }
};

const eventTitle = event => {
  const key = event.kind.toUpperCase();
  return t(`AUDIENCES.SHOW.EVENT.${key}`, {
    user: event.user_name || '—',
    campaign: event.campaign_title || '—',
  });
};

const eventDetail = event =>
  t('AUDIENCES.SHOW.EVENT_DETAIL', {
    date: format(new Date(event.created_at * 1000), 'dd/MM HH:mm'),
    count: event.contacts_count,
  });

const openSnapshot = () => {
  snapshotName.value = `${audience.value.name} · ${format(new Date(), 'dd/MM')}`;
  snapshotDialogRef.value?.open();
};

const snapshot = async () => {
  isWorking.value = true;
  try {
    const { data } = await AudiencesAPI.snapshot(
      audienceId.value,
      snapshotName.value
    );
    useAlert(t('AUDIENCES.SNAPSHOT_DIALOG.SUCCESS'));
    snapshotDialogRef.value?.close();
    router.push({
      name: 'marketing_audiences_show',
      params: { audienceId: data.payload.id },
    });
  } finally {
    isWorking.value = false;
  }
};

const removeContact = async contact => {
  await AudiencesAPI.removeContacts(audienceId.value, [contact.id]);
  useAlert(t('AUDIENCES.SHOW.REMOVED'));
  await fetchAudience();
};

const destroy = async () => {
  isWorking.value = true;
  try {
    await AudiencesAPI.delete(audienceId.value);
    useAlert(t('AUDIENCES.SHOW.DELETED'));
    router.push({ name: 'marketing_audiences_index' });
  } finally {
    isWorking.value = false;
  }
};

const edit = () =>
  router.push({
    name: 'marketing_audiences_edit',
    params: { audienceId: audienceId.value },
  });

onMounted(fetchAudience);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <button
        type="button"
        class="mb-2 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="router.push({ name: 'marketing_audiences_index' })"
      >
        {{ t('AUDIENCES.SHOW.BACK') }}
      </button>

      <div v-if="isLoading && !audience" class="flex justify-center py-10">
        <Spinner />
      </div>

      <template v-else-if="audience">
        <header class="flex flex-wrap items-start justify-between gap-4 mb-6">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <h1 class="mb-0 text-heading-1 text-n-slate-12">
                {{ audience.name }}
              </h1>
              <span
                class="px-2 py-0.5 text-xs rounded-md"
                :class="
                  isDynamic
                    ? 'bg-n-blue-3 text-n-blue-11'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{ t(`AUDIENCES.KIND.${audience.kind.toUpperCase()}`) }}
              </span>
            </div>
            <p class="mb-0 text-sm text-n-slate-11">
              {{
                t('AUDIENCES.SHOW.UPDATED', {
                  time: dynamicTime(audience.counted_at || audience.created_at),
                })
              }}
              {{
                isDynamic
                  ? t('AUDIENCES.SHOW.FED_BY_RULE')
                  : t('AUDIENCES.SHOW.STATIC_LIST')
              }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              :label="
                isDynamic
                  ? t('AUDIENCES.SHOW.EDIT')
                  : t('AUDIENCES.SHOW.RENAME')
              "
              icon="i-lucide-pencil"
              variant="faded"
              color="slate"
              size="sm"
              @click="edit"
            />
            <Button
              v-if="isDynamic"
              :label="t('AUDIENCES.SHOW.SNAPSHOT')"
              icon="i-lucide-snowflake"
              variant="faded"
              color="slate"
              size="sm"
              @click="openSnapshot"
            />
            <Button
              v-else
              :label="t('AUDIENCES.SHOW.ADD_CONTACTS')"
              icon="i-lucide-user-plus"
              variant="faded"
              color="slate"
              size="sm"
              @click="addContactsDialogRef?.open()"
            />
            <Button
              :label="t('AUDIENCES.SHOW.DELETE')"
              icon="i-lucide-trash-2"
              variant="faded"
              color="ruby"
              size="sm"
              @click="deleteDialogRef?.open()"
            />
          </div>
        </header>

        <p
          v-if="audience.over_limit"
          class="px-3 py-2 mb-4 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
        >
          {{ t('AUDIENCES.SHOW.OVER_LIMIT') }}
        </p>

        <div class="grid grid-cols-1 gap-3 mb-6 md:grid-cols-2">
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
            <p class="mb-1 text-xs text-n-slate-11">
              {{ t('AUDIENCES.SHOW.CONTACTS_COUNT') }}
            </p>
            <p class="mb-0 text-2xl font-semibold text-n-slate-12">
              {{ audience.contacts_count.toLocaleString() }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
            <p class="mb-1 text-xs text-n-slate-11">
              {{ t('AUDIENCES.SHOW.DOWNLOADS') }}
            </p>
            <p class="mb-0 text-2xl font-semibold text-n-slate-12">
              {{ recentDownloads }}
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div class="flex flex-col gap-3 lg:col-span-2">
            <h2 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('AUDIENCES.SHOW.CONTACTS_TITLE') }}
              <span class="text-xs font-normal text-n-slate-11">
                {{
                  t('AUDIENCES.SHOW.CONTACTS_SHOWING', {
                    shown: contacts.length,
                    total: contactsMeta.total_count,
                  })
                }}
              </span>
            </h2>
            <p
              v-if="!contacts.length"
              class="py-6 text-sm text-center text-n-slate-11"
            >
              {{ t('AUDIENCES.SHOW.NO_CONTACTS') }}
            </p>
            <div v-else class="overflow-x-auto border rounded-xl border-n-weak">
              <table class="w-full text-sm">
                <thead>
                  <tr
                    class="text-xs text-left border-b text-n-slate-11 border-n-weak"
                  >
                    <th class="px-3 py-2 font-medium">
                      {{ t('AUDIENCES.SHOW.TABLE.NAME') }}
                    </th>
                    <th class="px-3 py-2 font-medium">
                      {{ t('AUDIENCES.SHOW.TABLE.PHONE') }}
                    </th>
                    <th class="px-3 py-2 font-medium">
                      {{ t('AUDIENCES.SHOW.TABLE.STAGE') }}
                    </th>
                    <th class="px-3 py-2 font-medium">
                      {{ t('AUDIENCES.SHOW.TABLE.LABELS') }}
                    </th>
                    <th class="px-3 py-2 font-medium">
                      {{ t('AUDIENCES.SHOW.TABLE.INBOX') }}
                    </th>
                    <th v-if="!isDynamic" class="px-3 py-2" />
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="contact in contacts"
                    :key="contact.id"
                    class="border-b border-n-weak last:border-b-0"
                  >
                    <td class="px-3 py-2 text-n-slate-12">
                      {{ contact.name }}
                    </td>
                    <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                      {{ contact.phone_number || '—' }}
                    </td>
                    <td class="px-3 py-2 text-n-slate-11">
                      {{ contact.funnel_stage || '—' }}
                    </td>
                    <td class="px-3 py-2">
                      <div class="flex flex-wrap gap-1">
                        <span
                          v-for="label in contact.labels"
                          :key="label"
                          class="px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
                        >
                          {{ label }}
                        </span>
                      </div>
                    </td>
                    <td class="px-3 py-2 text-n-slate-11">
                      {{ contact.inbox_name || '—' }}
                    </td>
                    <td v-if="!isDynamic" class="px-3 py-2 text-right">
                      <Button
                        icon="i-lucide-user-minus"
                        variant="ghost"
                        color="slate"
                        size="sm"
                        :aria-label="t('AUDIENCES.SHOW.REMOVE')"
                        @click="removeContact(contact)"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <PaginationFooter
              v-if="contactsMeta.total_count > PER_PAGE"
              :current-page="contactsMeta.current_page"
              :total-items="contactsMeta.total_count"
              :items-per-page="PER_PAGE"
              @update:current-page="fetchContacts"
            />
          </div>

          <aside class="flex flex-col gap-4">
            <div
              v-if="isDynamic"
              class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-2"
            >
              <div>
                <p class="mb-1 text-xs font-medium text-n-slate-12">
                  {{ t('AUDIENCES.SHOW.RULE_TITLE') }}
                </p>
                <p
                  v-for="(condition, index) in audience.rule"
                  :key="index"
                  class="mb-0 text-xs text-n-slate-11"
                >
                  {{ describe(condition) }}
                </p>
                <p
                  v-if="!audience.rule.length"
                  class="mb-0 text-xs text-n-slate-11"
                >
                  {{ t('AUDIENCES.RULE.EVERYONE') }}
                </p>
              </div>
              <div>
                <p class="mb-1 text-xs font-medium text-n-slate-12">
                  {{ t('AUDIENCES.SHOW.WINDOW_TITLE') }}
                </p>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ describeWindow(audience.window) }}
                </p>
              </div>
              <div>
                <p class="mb-1 text-xs font-medium text-n-slate-12">
                  {{ t('AUDIENCES.SHOW.EXCLUSION_TITLE') }}
                </p>
                <p
                  v-for="(condition, index) in audience.exclusion"
                  :key="index"
                  class="mb-0 text-xs text-n-ruby-11"
                >
                  {{ t('AUDIENCES.RULE.EXCEPT') }} {{ describe(condition) }}
                </p>
                <p
                  v-if="!audience.exclusion.length"
                  class="mb-0 text-xs text-n-slate-11"
                >
                  {{ t('AUDIENCES.SHOW.NO_EXCLUSION') }}
                </p>
              </div>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.SHOW.RULE_NOTE') }}
              </p>
            </div>

            <div
              class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-2"
            >
              <p class="mb-0 text-xs font-medium text-n-slate-12">
                {{ t('AUDIENCES.SHOW.ACTIONS_TITLE') }}
              </p>
              <div v-for="event in events" :key="event.id">
                <p class="mb-0 text-xs text-n-slate-12">
                  {{ eventTitle(event) }}
                </p>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ eventDetail(event) }}
                </p>
              </div>
              <p v-if="!events.length" class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.SHOW.ACTIONS_EMPTY') }}
              </p>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('AUDIENCES.SHOW.ACTIONS_NOTE') }}
              </p>
            </div>
          </aside>
        </div>
      </template>
    </div>

    <Dialog
      ref="snapshotDialogRef"
      :title="t('AUDIENCES.SNAPSHOT_DIALOG.TITLE')"
      :description="
        t('AUDIENCES.SNAPSHOT_DIALOG.DESCRIPTION', {
          count: audience?.contacts_count ?? 0,
        })
      "
      :confirm-button-label="t('AUDIENCES.SNAPSHOT_DIALOG.CONFIRM')"
      :disable-confirm-button="!snapshotName.trim()"
      :is-loading="isWorking"
      @confirm="snapshot"
    >
      <Input
        v-model="snapshotName"
        :label="t('AUDIENCES.SNAPSHOT_DIALOG.NAME')"
      />
    </Dialog>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('AUDIENCES.SHOW.DELETE_TITLE')"
      :description="
        t('AUDIENCES.SHOW.DELETE_DESCRIPTION', { name: audience?.name || '' })
      "
      :confirm-button-label="t('AUDIENCES.SHOW.DELETE')"
      :is-loading="isWorking"
      @confirm="destroy"
    />

    <AddContactsDialog
      v-if="audience && !isDynamic"
      ref="addContactsDialogRef"
      :audience-id="audience.id"
      @added="fetchAudience"
    />
  </section>
</template>
