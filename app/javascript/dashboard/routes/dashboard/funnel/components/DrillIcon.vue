<script setup>
// "Opens" marker (square with an arrow out of it) drawn inside the report
// SVGs, next to a number that opens its drill-down. Positioned in the parent
// SVG's coordinates; colored by the parent through `currentColor`.
defineProps({
  x: { type: Number, required: true },
  y: { type: Number, required: true },
  size: { type: Number, default: 20 },
});
</script>

<template>
  <svg
    :x="x"
    :y="y"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2.5"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path d="M15 3h6v6" />
    <path d="M10 14 21 3" />
    <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
  </svg>
</template>
