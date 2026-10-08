<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  templateQualityKey,
  templateQualityWarns,
} from 'dashboard/helper/templateQuality';

// What a Média / Baixa / Pausado / Desativado template means for the clinic
// and what helps. `blocked` (campaigns) opens with why the send is refused.
// Renders nothing for Alta or a template not rated yet.
const props = defineProps({
  template: {
    type: Object,
    default: null,
  },
  blocked: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const TIPS = [
  'RECENT',
  'PERSONALIZE',
  'WHO_AND_WHY',
  'OPT_OUT',
  'FREQUENCY',
  'UTILITY',
  'NEW_VERSION',
];

const qualityKey = computed(() => templateQualityKey(props.template));
const quality = computed(() => t(`META_TEMPLATES.QUALITY.${qualityKey.value}`));
const isRefusedByMeta = computed(() =>
  ['PAUSED', 'DISABLED'].includes(qualityKey.value)
);

const title = computed(() => {
  if (props.blocked) {
    return isRefusedByMeta.value
      ? t('META_TEMPLATES.QUALITY.WARNING.BLOCKED', { quality: quality.value })
      : t('META_TEMPLATES.QUALITY.WARNING.BLOCKED_LOW');
  }
  return isRefusedByMeta.value
    ? t('META_TEMPLATES.QUALITY.WARNING.REFUSED', { quality: quality.value })
    : t('META_TEMPLATES.QUALITY.WARNING.TITLE', { quality: quality.value });
});
</script>

<template>
  <div
    v-if="templateQualityWarns(qualityKey)"
    role="alert"
    class="flex flex-col gap-1 px-3 py-2 rounded-lg text-xs"
    :class="
      blocked || isRefusedByMeta
        ? 'bg-n-ruby-3 text-n-ruby-11'
        : 'bg-n-amber-3 text-n-amber-11'
    "
  >
    <p class="mb-0">
      <strong class="font-semibold">{{ title }}</strong>
      {{ t('META_TEMPLATES.QUALITY.WARNING.BODY') }}
    </p>
    <p class="mb-0 font-semibold">
      {{ t('META_TEMPLATES.QUALITY.WARNING.HELPS') }}
    </p>
    <ul class="mb-0 pl-4 list-disc">
      <li v-for="tip in TIPS" :key="tip">
        {{ t(`META_TEMPLATES.QUALITY.WARNING.TIPS.${tip}`) }}
      </li>
    </ul>
  </div>
</template>
