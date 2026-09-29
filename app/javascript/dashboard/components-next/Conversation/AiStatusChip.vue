<script setup>
// Round "sparkle" chip for the AI status: filled green when the AI answers
// the conversation, outlined grey when it doesn't. Purely visual — no text,
// the caller supplies the label (tooltip / aria-label / text beside it).
defineProps({
  enabled: { type: Boolean, default: true },
  // `sm` fits dense rows (conversation list, funnel, menus); `md` is the
  // conversation header.
  size: {
    type: String,
    default: 'sm',
    validator: value => ['sm', 'md'].includes(value),
  },
});
</script>

<template>
  <span
    class="inline-flex items-center justify-center flex-shrink-0 rounded-full border"
    :class="[
      size === 'md' ? 'size-[26px]' : 'size-5',
      enabled
        ? 'bg-n-teal-3 border-n-teal-9 text-n-teal-9'
        : 'bg-n-solid-1 border-n-slate-11 text-n-slate-10',
    ]"
  >
    <svg
      :width="size === 'md' ? 14 : 12"
      :height="size === 'md' ? 14 : 12"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path
        d="M9.6 1 L11.5 7.7 L18.2 9.6 L11.5 11.5 L9.6 18.2 L7.7 11.5 L1 9.6 L7.7 7.7 Z"
        fill="currentColor"
      />
      <path
        d="M18 13.6 L19 16.6 L22 17.6 L19 18.6 L18 21.6 L17 18.6 L14 17.6 L17 16.6 Z"
        fill="currentColor"
      />
      <path
        d="M19.6 2.2 L20.2 4.4 L22.4 5 L20.2 5.6 L19.6 7.8 L19 5.6 L16.8 5 L19 4.4 Z"
        fill="currentColor"
      />
    </svg>
  </span>
</template>
