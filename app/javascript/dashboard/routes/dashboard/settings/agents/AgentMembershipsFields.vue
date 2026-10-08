<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

// The inboxes and teams the agent is in, picked from the agent's side. They
// are saved as the same inbox and team members the inbox and team screens
// manage — this is only another way to set them.
const inboxIds = defineModel('inboxIds', { type: Array, default: () => [] });
const teamIds = defineModel('teamIds', { type: Array, default: () => [] });

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');

onMounted(() => store.dispatch('teams/get'));

const fields = computed(() => [
  {
    key: 'INBOXES',
    model: inboxIds,
    options: (inboxes.value || []).map(({ id, name }) => ({
      value: id,
      label: name,
    })),
  },
  {
    key: 'TEAMS',
    model: teamIds,
    options: (teams.value || []).map(({ id, name }) => ({
      value: id,
      label: name,
    })),
  },
]);
</script>

<template>
  <div
    v-for="field in fields"
    :key="field.key"
    class="flex flex-col gap-1 w-full mb-4"
  >
    <span class="text-sm font-medium text-n-slate-12">
      {{ t(`AGENT_MGMT.MEMBERSHIPS.${field.key}.LABEL`) }}
    </span>
    <TagMultiSelectComboBox
      :model-value="field.model.value"
      :options="field.options"
      :placeholder="t(`AGENT_MGMT.MEMBERSHIPS.${field.key}.PLACEHOLDER`)"
      :empty-state="t(`AGENT_MGMT.MEMBERSHIPS.${field.key}.EMPTY`)"
      @update:model-value="value => (field.model.value = [...value])"
    />
    <div class="flex items-center gap-4 text-sm">
      <button
        type="button"
        class="text-n-blue-text hover:underline"
        :disabled="!field.options.length"
        @click="field.model.value = field.options.map(option => option.value)"
      >
        {{ t('AGENT_MGMT.MEMBERSHIPS.SELECT_ALL') }}
      </button>
      <button
        type="button"
        class="text-n-blue-text hover:underline"
        @click="field.model.value = []"
      >
        {{ t('AGENT_MGMT.MEMBERSHIPS.CLEAR') }}
      </button>
    </div>
  </div>
</template>
