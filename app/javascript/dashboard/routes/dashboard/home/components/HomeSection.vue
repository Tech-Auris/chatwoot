<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// One block of the Início page, drawn as its section of the cards arrives.
// While it reloads, the last numbers stay on screen, faded under a spinner;
// a section that fails shows the error in its own blocks only.
defineProps({
  title: { type: String, required: true },
  // The section's numbers are on screen.
  ready: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
});

const emit = defineEmits(['retry']);

const { t } = useI18n();
</script>

<template>
  <div class="relative">
    <template v-if="ready">
      <div
        class="h-full transition-opacity"
        :class="{ 'opacity-50 pointer-events-none': loading }"
      >
        <slot />
      </div>
      <Spinner
        v-if="loading"
        :size="16"
        class="absolute top-3 right-4 text-n-brand"
      />
    </template>
    <div
      v-else
      class="flex flex-col h-full gap-2 px-4 py-3 min-h-28 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
    >
      <div class="flex items-center justify-between text-sm text-n-slate-11">
        {{ title }}
        <Spinner v-if="!error" :size="16" class="text-n-brand" />
      </div>
      <template v-if="error">
        <p class="mb-0 text-sm text-n-ruby-11">
          {{ t('HOME_OVERVIEW.SECTION_ERROR') }}
        </p>
        <Button
          link
          sm
          class="self-start"
          :label="t('HOME_OVERVIEW.RETRY')"
          @click="emit('retry')"
        />
      </template>
    </div>
  </div>
</template>
