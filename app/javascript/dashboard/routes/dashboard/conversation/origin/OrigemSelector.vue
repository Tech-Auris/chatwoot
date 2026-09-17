<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import { ORIGEM_OPTIONS } from 'dashboard/helper/origemOptions';
import ContactDetailsItem from '../ContactDetailsItem.vue';

// Scoped to the CURRENT conversation — origem is per-conversation now
// (see feat/conversation-origem-foundation). State comes straight from
// the open chat, no props needed.

const store = useStore();
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');

const currentOrigem = computed(() => currentChat.value?.origem || null);

const dropdownOptions = computed(() => [
  { id: null, name: t('CONVERSATION_ORIGIN.NONE') },
  ...ORIGEM_OPTIONS.map(value => ({ id: value, name: value })),
]);

const selectedItem = computed(
  () =>
    dropdownOptions.value.find(opt => opt.id === currentOrigem.value) ||
    dropdownOptions.value[0]
);

const onSelect = async selected => {
  const nextValue = selected?.id ?? null;
  if (nextValue === currentOrigem.value) return;
  if (!currentChat.value?.id) return;

  try {
    await store.dispatch('updateOrigem', {
      conversationId: currentChat.value.id,
      origem: nextValue,
    });
    useAlert(t('CONVERSATION_ORIGIN.UPDATE_SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION_ORIGIN.UPDATE_ERROR'));
  }
};
</script>

<template>
  <div>
    <ContactDetailsItem compact :title="t('CONVERSATION_ORIGIN.TITLE')" />
    <MultiselectDropdown
      :options="dropdownOptions"
      :selected-item="selectedItem"
      :has-thumbnail="false"
      :multiselector-title="t('CONVERSATION_ORIGIN.TITLE')"
      :multiselector-placeholder="t('CONVERSATION_ORIGIN.NONE')"
      :no-search-result="t('CONVERSATION_ORIGIN.NO_RESULT')"
      :input-placeholder="t('CONVERSATION_ORIGIN.SEARCH_PLACEHOLDER')"
      @select="onSelect"
    />
  </div>
</template>
