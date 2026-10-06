<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'next/avatar/Avatar.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import {
  useMapGetter,
  useStoreGetters,
  useStore,
} from 'dashboard/composables/store';
import ChannelName from './components/ChannelName.vue';
import {
  connectionKey,
  inboxAddress,
  matchesQuery,
} from './helpers/inboxListFilter';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import InboxStatusBadge from 'dashboard/components-next/Inbox/InboxStatusBadge.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const getters = useStoreGetters();
const store = useStore();
const { t, te } = useI18n();
const currentRole = computed(() => getters.getCurrentRole.value);
const isAdmin = computed(() => currentRole.value === 'administrator');
const canConfigureInboxes = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

const showDeletePopup = ref(false);
const selectedInbox = ref({});
const searchQuery = ref('');
const providerFilter = ref('');

const inboxes = useMapGetter('inboxes/getInboxes');

const inboxesList = computed(() => {
  return inboxes.value?.slice().sort((a, b) => a.name.localeCompare(b.name));
});

const connectionLabel = key => {
  const listKey = `INBOX_MGMT.LIST.CONNECTION_FILTER.${key}`;
  return te(listKey) ? t(listKey) : t(`INBOX_MGMT.CHANNELS.${key}`);
};

// Only the kinds this account actually has.
const connectionOptions = computed(() => {
  const keys = [...new Set((inboxesList.value || []).map(connectionKey))];
  return [
    { value: '', label: t('INBOX_MGMT.LIST.CONNECTION_FILTER.ALL') },
    ...keys
      .map(key => ({ value: key, label: connectionLabel(key) }))
      .sort((a, b) => a.label.localeCompare(b.label)),
  ];
});

const filteredInboxesList = computed(() => {
  const query = searchQuery.value.trim();
  return (inboxesList.value || []).filter(
    inbox =>
      (!providerFilter.value ||
        connectionKey(inbox) === providerFilter.value) &&
      (!query || matchesQuery(inbox, query))
  );
});

const tableHeaders = computed(() => [
  t('INBOX_MGMT.LIST.COLUMNS.NAME'),
  t('INBOX_MGMT.LIST.COLUMNS.ADDRESS'),
  t('INBOX_MGMT.LIST.COLUMNS.STATUS'),
  t('INBOX_MGMT.LIST.COLUMNS.QUALITY'),
  t('INBOX_MGMT.LIST.COLUMNS.ID'),
  t('INBOX_MGMT.LIST.COLUMNS.ACTIONS'),
]);

const uiFlags = computed(() => getters['inboxes/getUIFlags'].value);

const deleteConfirmText = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.YES')} ${selectedInbox.value.name}`
);

const deleteRejectText = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.NO')} ${selectedInbox.value.name}`
);

const confirmDeleteMessage = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.MESSAGE')} ${selectedInbox.value.name}?`
);
const confirmPlaceHolderText = computed(
  () =>
    `${t('INBOX_MGMT.DELETE.CONFIRM.PLACE_HOLDER', {
      inboxName: selectedInbox.value.name,
    })}`
);

const deleteInbox = async ({ id }) => {
  try {
    await store.dispatch('inboxes/delete', id);
    useAlert(t('INBOX_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.DELETE.API.ERROR_MESSAGE'));
  }
};
const closeDelete = () => {
  showDeletePopup.value = false;
  selectedInbox.value = {};
};

const confirmDeletion = () => {
  deleteInbox(selectedInbox.value);
  closeDelete();
};
const openDelete = inbox => {
  showDeletePopup.value = true;
  selectedInbox.value = inbox;
};
</script>

<template>
  <SettingsLayout
    :no-records-found="!inboxesList.length"
    :no-records-message="$t('INBOX_MGMT.LIST.404')"
    :is-loading="uiFlags.isFetching"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('INBOX_MGMT.HEADER')"
        :description="$t('INBOX_MGMT.DESCRIPTION')"
        :link-text="$t('INBOX_MGMT.LEARN_MORE')"
        :search-placeholder="$t('INBOX_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="inboxes"
      >
        <template v-if="inboxesList?.length" #tabs>
          <Select
            v-model="providerFilter"
            :options="connectionOptions"
            class="[&>select]:!py-1.5"
          />
        </template>
        <template v-if="inboxesList?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('INBOX_MGMT.COUNT', { n: filteredInboxesList.length }) }}
          </span>
        </template>
        <template #actions>
          <router-link v-if="isAdmin" :to="{ name: 'settings_inbox_new' }">
            <Button :label="$t('SETTINGS.INBOXES.NEW_INBOX')" size="sm" />
          </router-link>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="filteredInboxesList"
        :no-data-message="searchQuery ? $t('INBOX_MGMT.NO_RESULTS') : ''"
      >
        <!-- The table capitalizes every word; these headers are phrases. -->
        <template
          v-for="index in [0, 1]"
          :key="index"
          #[`header-${index}`]="{ header }"
        >
          <span class="normal-case">{{ header }}</span>
        </template>
        <template #row="{ items }">
          <BaseTableRow v-for="inbox in items" :key="inbox.id" :item="inbox">
            <template #default>
              <BaseTableCell>
                <div class="flex items-center gap-4 min-w-0">
                  <div
                    v-if="inbox.avatar_url"
                    class="bg-n-alpha-3 rounded-xl size-10 shrink-0 ring ring-n-solid-1 border border-n-strong shadow-sm grid place-items-center"
                  >
                    <Avatar
                      :src="inbox.avatar_url"
                      :name="inbox.name"
                      :size="24"
                      rounded-full
                    />
                  </div>
                  <div
                    v-else
                    class="size-10 shrink-0 justify-center bg-n-alpha-3 rounded-xl ring ring-n-solid-1 border border-n-strong shadow-sm grid place-items-center"
                  >
                    <ChannelIcon
                      class="size-6 text-n-slate-10"
                      :inbox="inbox"
                    />
                  </div>
                  <div class="flex flex-col items-start gap-1 min-w-0">
                    <span
                      class="block text-body-main text-n-slate-12 capitalize"
                    >
                      {{ inbox.name }}
                    </span>
                    <ChannelName
                      :channel-type="inbox.channel_type"
                      :medium="inbox.medium"
                      :voice-enabled="inbox.voice_enabled"
                      class="text-body-main text-n-slate-11"
                      :provider="inbox.provider"
                    />
                  </div>
                </div>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 break-all">
                  {{ inboxAddress(inbox) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <InboxStatusBadge :inbox="inbox" only="status" />
              </BaseTableCell>
              <BaseTableCell>
                <InboxStatusBadge :inbox="inbox" only="quality" />
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 tabular-nums">
                  {{ inbox.id }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end">
                <div class="flex gap-3 justify-end flex-shrink-0">
                  <router-link
                    :to="{
                      name: 'settings_inbox_show',
                      params: { inboxId: inbox.id },
                    }"
                  >
                    <Button
                      v-if="canConfigureInboxes"
                      v-tooltip.top="$t('INBOX_MGMT.SETTINGS')"
                      icon="i-woot-settings"
                      slate
                      sm
                    />
                  </router-link>
                  <Button
                    v-if="isAdmin"
                    v-tooltip.top="$t('INBOX_MGMT.DELETE.BUTTON_TEXT')"
                    icon="i-woot-bin"
                    slate
                    sm
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    @click="openDelete(inbox)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <woot-confirm-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :title="$t('INBOX_MGMT.DELETE.CONFIRM.TITLE')"
      :message="confirmDeleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
      :confirm-value="selectedInbox.name"
      :confirm-place-holder-text="confirmPlaceHolderText"
      @on-confirm="confirmDeletion"
      @on-close="closeDelete"
    />
  </SettingsLayout>
</template>
