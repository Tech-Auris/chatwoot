<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import VirtualClinicShell from './components/VirtualClinicShell.vue';
import TeamPanel from './components/TeamPanel.vue';
import AiChatPanel from './components/AiChatPanel.vue';
import ClinicMap from './components/ClinicMap.vue';
import { useVirtualClinicConfig } from './composables/useVirtualClinicConfig';
import { useVirtualClinicStatus } from './composables/useVirtualClinicStatus';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { currentAccount } = useAccount();
const { configs, load } = useVirtualClinicConfig();
const selectedMember = ref('');
const thinking = ref('');

const clinicName = computed(() => currentAccount.value?.name || '');
const aiTeam = computed(() => configs.value[route.params.accountId] || null);
const { status } = useVirtualClinicStatus(
  computed(() => aiTeam.value?.visible === true)
);
const openMember = computed(() => {
  if (!aiTeam.value?.chat_enabled) return null;
  return aiTeam.value.members.find(m => m.persona === selectedMember.value);
});

const closeChat = () => {
  selectedMember.value = '';
  if (route.query.member) router.replace({ query: {} });
};

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
      :status="status"
      :selected="selectedMember"
      @select-member="selectedMember = $event"
    />
    <ClinicMap
      :ai-team="aiTeam"
      :status="status"
      :thinking="thinking"
      :focused="openMember?.persona || ''"
      @select-member="selectedMember = $event"
    />
    <AiChatPanel
      v-if="openMember"
      :key="openMember.persona"
      :member="openMember"
      @thinking="thinking = $event"
      @close="closeChat"
    />
  </VirtualClinicShell>
</template>
