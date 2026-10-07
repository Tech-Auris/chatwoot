<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  templateQualityKey,
  templateQualityStyle,
  templateScore,
} from 'dashboard/helper/templateQuality';

// A template's quality as Meta rates it: dot + Alta / Média / Baixa / Sem
// classificação ainda, or Pausado / Desativado pelo Meta.
const props = defineProps({
  template: {
    type: Object,
    default: null,
  },
  // Only the rating, for screens that already show the status apart.
  scoreOnly: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const qualityKey = computed(() =>
  props.scoreOnly
    ? templateScore(props.template)
    : templateQualityKey(props.template)
);
const style = computed(() => templateQualityStyle(qualityKey.value));
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-xs font-medium whitespace-nowrap"
    :class="style.badge"
  >
    <span class="size-1.5 rounded-full shrink-0" :class="style.dot" />
    {{ t(`META_TEMPLATES.QUALITY.${qualityKey}`) }}
  </span>
</template>
