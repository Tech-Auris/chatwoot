<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import TeamPanel from './components/TeamPanel.vue';

const { t } = useI18n();
const { currentAccount } = useAccount();
const aiTeam = ref(null);
const selectedMember = ref('');

const clinicName = computed(() => currentAccount.value?.name || '');

onMounted(async () => {
  const { data } = await VirtualClinicAPI.getConfig();
  aiTeam.value = data.ai_team;
});
</script>

<template>
  <div class="flex w-full h-full overflow-hidden bg-n-background">
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
  </div>
</template>
