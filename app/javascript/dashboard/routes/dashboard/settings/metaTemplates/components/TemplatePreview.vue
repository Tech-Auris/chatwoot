<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// WhatsApp-style live preview of a Meta template. Renders the same
// visual shape the recipient sees on their phone — chat-bubble with
// header / body / footer / buttons. Placeholders (`{{n}}`) are replaced
// with the provided sample values when present, otherwise shown in
// dimmed monospace so the operator sees exactly which slots are still
// unfilled.
//
// Not attempting full device-frame fidelity (background wallpaper,
// timestamp, avatar) — that belongs to Fatia 5. The bubble alone gives
// the operator enough to trust what Meta will show.

const props = defineProps({
  header: {
    type: Object,
    default: null,
    // Shapes accepted:
    //   { format: 'TEXT', text: 'Hello {{1}}' }             — 3b
    //   { format: 'IMAGE', mediaPreviewUrl: 'blob:...' }    — 3c (create)
  },
  body: {
    type: String,
    default: '',
  },
  bodySamples: {
    type: Object,
    default: () => ({}), // { '1': 'Fabio', '2': '12/08/2026' }
  },
  footer: {
    type: String,
    default: '',
  },
  buttons: {
    type: Array,
    default: () => [], // [{ type: 'QUICK_REPLY', text: 'Confirmar' }, ...]
  },
});

const { t } = useI18n();

const renderPlaceholders = text => {
  if (!text) return '';
  return text.replace(/\{\{(\d+)\}\}/g, (match, index) => {
    const sample = props.bodySamples[index];
    return sample?.trim() ? sample : match;
  });
};

const headerFormat = computed(() =>
  (props.header?.format || 'TEXT').toUpperCase()
);
const renderedHeader = computed(() => {
  if (!props.header?.text) return '';
  return renderPlaceholders(props.header.text);
});
const headerImageUrl = computed(() =>
  headerFormat.value === 'IMAGE' ? props.header?.mediaPreviewUrl : null
);

const renderedBody = computed(() => renderPlaceholders(props.body));
</script>

<template>
  <div class="w-full max-w-sm">
    <div class="text-xs text-n-slate-11 mb-2 uppercase tracking-wide">
      {{ t('META_TEMPLATES.PREVIEW.TITLE') }}
    </div>
    <div
      class="bg-[#e5ddd5] dark:bg-n-slate-4 rounded-2xl p-4 shadow-sm border border-n-weak"
    >
      <!-- Bubble -->
      <div
        class="bg-white dark:bg-n-solid-2 rounded-lg p-3 shadow text-sm text-n-slate-12 max-w-full"
      >
        <img
          v-if="headerImageUrl"
          :src="headerImageUrl"
          :alt="t('META_TEMPLATES.PREVIEW.HEADER_IMAGE_ALT')"
          class="w-full rounded-md object-cover mb-2 max-h-64"
        />
        <div
          v-if="renderedHeader"
          class="font-semibold text-base leading-snug mb-2 whitespace-pre-wrap break-words"
        >
          {{ renderedHeader }}
        </div>

        <div
          v-if="renderedBody"
          class="whitespace-pre-wrap break-words leading-relaxed"
        >
          {{ renderedBody }}
        </div>
        <div v-else class="italic text-n-slate-10">
          {{ t('META_TEMPLATES.PREVIEW.EMPTY_BODY') }}
        </div>

        <div
          v-if="footer"
          class="text-xs text-n-slate-11 mt-2 whitespace-pre-wrap break-words"
        >
          {{ footer }}
        </div>
      </div>

      <!-- Buttons live outside the bubble, matching WhatsApp UX -->
      <div v-if="buttons.length" class="mt-2 grid gap-1">
        <div
          v-for="(button, idx) in buttons"
          :key="idx"
          class="bg-white dark:bg-n-solid-2 rounded-lg py-2 px-3 text-center text-sm font-medium border border-n-weak"
          :class="
            button.type === 'QUICK_REPLY' ? 'text-n-slate-12' : 'text-n-blue-11'
          "
        >
          {{ button.text || t('META_TEMPLATES.PREVIEW.BUTTON_PLACEHOLDER') }}
        </div>
      </div>
    </div>
  </div>
</template>
