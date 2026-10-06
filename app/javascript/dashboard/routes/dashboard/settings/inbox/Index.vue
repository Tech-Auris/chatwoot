<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import Avatar from 'next/avatar/Avatar.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import {
  useMapGetter,
  useStoreGetters,
  useStore,
} from 'dashboard/composables/store';
import ChannelName from './components/ChannelName.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import InboxStatusBadge from 'dashboard/components-next/Inbox/InboxStatusBadge.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const currentRole = computed(() => getters.getCurrentRole.value);
const isAdmin = computed(() => currentRole.value === 'administrator');
const canConfigureInboxes = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

const showDeletePopup = ref(false);
const selectedInbox = ref({});
const searchQuery = ref('');

const inboxes = useMapGetter('inboxes/getInboxes');

const inboxesList = computed(() => {
  return inboxes.value?.slice().sort((a, b) => a.name.localeCompare(b.name));
});

const filteredInboxesList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return inboxesList.value;
  return picoSearch(inboxesList.value, query, [
    'name',
    'channel_type',
    'phone_number',
  ]);
});

// What the customer sees on the other side: the number, the @ or the site.
const inboxAddress = inbox => {
  if (inbox.phone_number) return inbox.phone_number;
  if (inbox.channel_type === 'Channel::Instagram') return `@${inbox.name}`;
  if (inbox.channel_type === 'Channel::Telegram' && inbox.bot_name)
    return `@${inbox.bot_name}`;
  return inbox.website_url || inbox.email || '—';
};

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
        <template v-if="inboxesList?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('INBOX_MGMT.COUNT', { n: inboxesList.length }) }}
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
      <span
        v-if="!filteredInboxesList.length && searchQuery"
        class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ $t('INBOX_MGMT.NO_RESULTS') }}
      </span>
      <div v-else class="divide-y divide-n-weak border-t border-n-weak">
        <div
          class="hidden md:grid grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)_minmax(0,1.4fr)_4.5rem_5rem] gap-4 py-2 text-xs font-medium uppercase tracking-wide text-n-slate-11"
        >
          <span>{{ $t('INBOX_MGMT.LIST.COLUMNS.NAME') }}</span>
          <span>{{ $t('INBOX_MGMT.LIST.COLUMNS.ADDRESS') }}</span>
          <span>{{ $t('INBOX_MGMT.LIST.COLUMNS.STATUS') }}</span>
          <span>{{ $t('INBOX_MGMT.LIST.COLUMNS.ID') }}</span>
          <span />
        </div>
        <div
          v-for="inbox in filteredInboxesList"
          :key="inbox.id"
          class="grid grid-cols-[minmax(0,1fr)_auto] md:grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)_minmax(0,1.4fr)_4.5rem_5rem] items-center gap-x-4 gap-y-2 py-4"
        >
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
              <ChannelIcon class="size-6 text-n-slate-10" :inbox="inbox" />
            </div>
            <div class="flex flex-col items-start gap-1 min-w-0">
              <span
                class="block text-heading-3 text-n-slate-12 capitalize truncate max-w-full"
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
          <span
            class="col-span-2 md:col-span-1 order-3 md:order-none text-body-main text-n-slate-12 truncate"
          >
            {{ inboxAddress(inbox) }}
          </span>
          <div class="col-span-2 md:col-span-1 order-4 md:order-none min-w-0">
            <InboxStatusBadge :inbox="inbox" />
          </div>
          <span
            class="col-span-2 md:col-span-1 order-5 md:order-none text-body-main text-n-slate-11 tabular-nums"
          >
            <span class="md:hidden">
              {{ $t('INBOX_MGMT.LIST.COLUMNS.ID') }}:
            </span>
            {{ inbox.id }}
          </span>
          <div class="flex gap-3 justify-end order-2 md:order-none">
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
        </div>
      </div>
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
