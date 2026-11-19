<script setup>
import { onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useVirtualClinicConfig } from '../composables/useVirtualClinicConfig';

// "Equipe de IA" at the bottom of the chat list: talking to Clara or Helena
// happens on the map, so a click goes there with the member selected.
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { configs, load } = useVirtualClinicConfig();

onMounted(() => load(route.params.accountId));

const openMember = persona =>
  router.push({
    name: 'virtual_clinic_index',
    params: { accountId: route.params.accountId },
    query: { member: persona },
  });
</script>

<template>
  <div v-if="configs[route.params.accountId]?.visible" class="mb-3">
    <h3
      class="flex items-center gap-1.5 px-2 py-1 text-xs font-semibold uppercase tracking-wider text-n-slate-10"
    >
      <Icon icon="i-lucide-sparkles" class="size-3" />
      {{ t('VIRTUAL_CLINIC.AI_TEAM.CHAT_SECTION') }}
    </h3>
    <button
      v-for="member in configs[route.params.accountId].members"
      :key="member.persona"
      type="button"
      class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
      @click="openMember(member.persona)"
    >
      <span
        class="grid text-[10px] font-semibold rounded-full size-5 place-items-center bg-n-teal-3 text-n-teal-11"
      >
        {{ member.name.charAt(0) }}
      </span>
      <span class="flex-1 text-left truncate">
        {{ member.name }} ·
        {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
      </span>
    </button>
  </div>
</template>
