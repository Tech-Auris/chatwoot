<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HelenaNews from './HelenaNews.vue';

// The manager for whoever can't talk to the AI team: only her news (new
// notifications, a new version), no chat.
const props = defineProps({
  member: { type: Object, required: true },
  news: { type: Object, required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();

const empty = computed(
  () => !props.news.notifications.length && !props.news.release
);
</script>

<template>
  <aside
    class="flex flex-col h-full border-l w-[22rem] shrink-0 border-n-weak bg-n-solid-1"
  >
    <header class="flex items-center gap-3 px-4 py-3 border-b border-n-weak">
      <span
        class="grid text-sm font-semibold rounded-full size-9 place-items-center bg-n-teal-3 text-n-teal-11"
      >
        {{ member.name.charAt(0) }}
      </span>
      <span class="flex-1 text-sm font-semibold text-n-slate-12">
        {{ member.name }}
        <span class="ml-1 text-xs font-medium text-n-teal-11">
          {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
        </span>
      </span>
      <Button
        icon="i-lucide-x"
        variant="ghost"
        color="slate"
        size="xs"
        @click="emit('close')"
      />
    </header>
    <div class="flex flex-col gap-3 p-4 overflow-y-auto">
      <p class="text-sm text-n-slate-11">
        {{
          empty
            ? t('VIRTUAL_CLINIC.NEWS.NOTHING', { name: member.name })
            : t('VIRTUAL_CLINIC.NEWS.HELLO', { name: member.name })
        }}
      </p>
      <HelenaNews :notifications="news.notifications" :release="news.release" />
    </div>
  </aside>
</template>
