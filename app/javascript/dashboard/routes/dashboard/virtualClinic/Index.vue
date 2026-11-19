<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import VirtualClinicShell from './components/VirtualClinicShell.vue';
import TeamPanel from './components/TeamPanel.vue';
import { useVirtualClinicConfig } from './composables/useVirtualClinicConfig';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { currentAccount } = useAccount();
const { configs, load } = useVirtualClinicConfig();
const selectedMember = ref('');

const clinicName = computed(() => currentAccount.value?.name || '');
const aiTeam = computed(() => configs.value[route.params.accountId] || null);

// The chat list sends people here with `?member=` to open an AI teammate.
watch(
  () => route.query.member,
  member => {
    if (member) selectedMember.value = member;
  },
  { immediate: true }
);

onMounted(() => {
  load(route.params.accountId);
  store.dispatch('agents/get');
});
</script>

<template>
  <VirtualClinicShell>
    <TeamPanel
      :clinic-name="clinicName"
      :ai-team="aiTeam"
      :selected="selectedMember"
      @select-member="selectedMember = $event"
    />
    <main class="relative flex-1 overflow-hidden bg-n-alpha-1">
      <p
        class="absolute text-sm -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2 text-n-slate-11"
      >
        {{ t('VIRTUAL_CLINIC.MAP_COMING') }}
      </p>
    </main>
  </VirtualClinicShell>
</template>
