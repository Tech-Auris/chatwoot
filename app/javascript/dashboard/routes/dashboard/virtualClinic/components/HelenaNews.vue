<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// What the manager tells the person on top of the clinic alerts: new
// notifications (with a link to the notification center) and a new version
// of the app (a summary and a link to the release notes).
defineProps({
  notifications: { type: Array, default: () => [] },
  // `{ tag, summary: [titles] }` or null.
  release: { type: Object, default: null },
});

const { t } = useI18n();
const SHOWN = 3;
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-if="notifications.length"
      class="flex flex-col gap-2 p-3 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
    >
      <p class="flex items-center gap-1.5 font-medium">
        <Icon icon="i-lucide-bell" class="size-4 text-n-amber-11" />
        {{ t('VIRTUAL_CLINIC.NEWS.NOTIFICATIONS', notifications.length) }}
      </p>
      <ul class="flex flex-col gap-1 pl-5 text-n-slate-11 list-disc">
        <li
          v-for="item in notifications.slice(0, SHOWN)"
          :key="item.id"
          class="truncate"
        >
          {{ item.push_message_title }}
        </li>
      </ul>
      <router-link :to="{ name: 'inbox_view' }" class="self-start">
        <Button
          :label="t('VIRTUAL_CLINIC.NEWS.OPEN_NOTIFICATIONS')"
          size="xs"
          variant="faded"
          color="slate"
        />
      </router-link>
    </div>

    <div
      v-if="release"
      class="flex flex-col gap-2 p-3 text-sm rounded-xl bg-n-iris-2 text-n-slate-12"
    >
      <p class="flex items-center gap-1.5 font-medium">
        <Icon icon="i-lucide-sparkles" class="size-4 text-n-iris-11" />
        {{ t('VIRTUAL_CLINIC.NEWS.RELEASE', { tag: release.tag }) }}
      </p>
      <ul class="flex flex-col gap-1 pl-5 text-n-slate-11 list-disc">
        <li v-for="title in release.summary" :key="title">{{ title }}</li>
      </ul>
      <router-link :to="{ name: 'release_notes_index' }" class="self-start">
        <Button
          :label="t('VIRTUAL_CLINIC.NEWS.OPEN_RELEASE')"
          size="xs"
          variant="faded"
          color="slate"
        />
      </router-link>
    </div>
  </div>
</template>
