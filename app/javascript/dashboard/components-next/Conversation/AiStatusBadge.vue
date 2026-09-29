<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import AiStatusChip from './AiStatusChip.vue';

// The AI status chip of a conversation; clicking toggles it. The state is in
// the colour and spelled out in the tooltip / aria-label.
const props = defineProps({
  conversationId: { type: Number, required: true },
  aiEnabled: { type: Boolean, default: true },
  // `sm` fits the dense rows (conversation list, funnel); `md` is the
  // conversation header.
  size: {
    type: String,
    default: 'sm',
    validator: value => ['sm', 'md'].includes(value),
  },
});

const { t } = useI18n();
const store = useStore();
const isToggling = ref(false);

const stateLabel = computed(() =>
  props.aiEnabled
    ? t('CONVERSATION.AI_STATUS.ON_LABEL')
    : t('CONVERSATION.AI_STATUS.OFF_LABEL')
);

const tooltip = computed(
  () =>
    `${stateLabel.value} · ${
      props.aiEnabled
        ? t('CONVERSATION.AI_STATUS.TOGGLE_OFF_TOOLTIP')
        : t('CONVERSATION.AI_STATUS.TOGGLE_ON_TOOLTIP')
    }`
);

const toggle = async () => {
  if (isToggling.value) return;
  isToggling.value = true;
  try {
    await store.dispatch('toggleAiStatus', {
      conversationId: props.conversationId,
    });
  } catch (error) {
    useAlert(t('CONVERSATION.AI_STATUS.TOGGLE_ERROR'));
  } finally {
    isToggling.value = false;
  }
};
</script>

<template>
  <button
    type="button"
    class="inline-flex flex-shrink-0 rounded-full transition-opacity hover:opacity-80 disabled:opacity-60 cursor-pointer"
    :disabled="isToggling"
    :title="tooltip"
    :aria-label="stateLabel"
    :aria-pressed="aiEnabled"
    @click.stop.prevent="toggle"
  >
    <AiStatusChip :enabled="aiEnabled" :size="size" />
  </button>
</template>
