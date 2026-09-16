<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import ContactDetailsItem from '../ContactDetailsItem.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

// Fixed vocabulary — must stay in sync with Contacts::OriginAttributionService::OPTIONS
// on the backend. Order carries no meaning; the empty first item is the
// "Sem Origem" reset that clears whatever the incoming pipeline auto-picked.
const OPTIONS = [
  'Evento',
  'Facebook',
  'Google',
  'Indicação de cliente',
  'Indicação de colega',
  'Influenciador',
  'Instagram',
  'Orgânico',
];

const store = useStore();
const { t } = useI18n();
const contactGetter = useMapGetter('contacts/getContact');

const contact = computed(() => contactGetter.value(props.contactId));
const currentOrigem = computed(
  () => contact.value?.additional_attributes?.origem || null
);

const dropdownOptions = computed(() => [
  { id: null, name: t('CONVERSATION_ORIGIN.NONE') },
  ...OPTIONS.map(value => ({ id: value, name: value })),
]);

const selectedItem = computed(
  () =>
    dropdownOptions.value.find(opt => opt.id === currentOrigem.value) ||
    dropdownOptions.value[0]
);

const onSelect = async selected => {
  const nextValue = selected?.id ?? null;
  if (nextValue === currentOrigem.value) return;

  try {
    await store.dispatch('contacts/update', {
      id: props.contactId,
      additional_attributes: {
        ...(contact.value?.additional_attributes || {}),
        origem: nextValue,
      },
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
