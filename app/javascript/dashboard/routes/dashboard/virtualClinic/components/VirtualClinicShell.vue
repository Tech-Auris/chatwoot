<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// Gather-style frame: a rail to switch between the clinic map and the
// internal chat. Without `enabled` it renders the content alone, so the
// internal chat keeps its old layout on accounts not released yet.
defineProps({ enabled: { type: Boolean, default: true } });

const route = useRoute();
const { t } = useI18n();
const unreadCount = useMapGetter('internalChat/getUnreadCount');

const onChat = computed(() => String(route.name).startsWith('internal_chat'));
const modes = computed(() => [
  {
    key: 'map',
    icon: 'i-lucide-map',
    label: t('VIRTUAL_CLINIC.RAIL.MAP'),
    to: { name: 'virtual_clinic_index', params: route.params },
    active: !onChat.value,
  },
  {
    key: 'chat',
    icon: 'i-lucide-messages-square',
    label: t('VIRTUAL_CLINIC.RAIL.CHAT'),
    to: {
      name: 'internal_chat_home',
      params: { accountId: route.params.accountId },
    },
    active: onChat.value,
    badge: unreadCount.value,
  },
]);
</script>

<template>
  <div class="flex w-full h-full">
    <nav
      v-if="enabled"
      class="flex flex-col items-center w-14 gap-2 pt-3 border-r shrink-0 border-n-weak bg-n-solid-2"
    >
      <router-link
        v-for="mode in modes"
        :key="mode.key"
        :to="mode.to"
        :title="mode.label"
        class="relative grid rounded-xl size-10 place-items-center"
        :class="
          mode.active
            ? 'bg-n-solid-1 text-n-brand shadow-sm'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
      >
        <Icon :icon="mode.icon" class="size-5" />
        <span
          v-if="mode.badge"
          class="absolute -top-1 -right-1 min-w-4 px-1 rounded-full bg-n-ruby-9 text-[10px] font-semibold text-white"
        >
          {{ mode.badge }}
        </span>
      </router-link>
    </nav>
    <div class="flex flex-1 min-w-0">
      <slot />
    </div>
  </div>
</template>
