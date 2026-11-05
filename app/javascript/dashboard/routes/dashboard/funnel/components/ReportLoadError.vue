<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  message: { type: String, required: true },
});

const emit = defineEmits(['retry']);
</script>

<template>
  <div class="flex flex-col items-center gap-3 py-10 text-center">
    <span class="text-sm text-n-slate-11">{{ message }}</span>
    <Button
      :label="$t('REPORT.RETRY')"
      icon="i-lucide-refresh-cw"
      variant="faded"
      color="slate"
      size="sm"
      @click="emit('retry')"
    />
  </div>
</template>
