<script setup>
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  to: { type: [Object, String], default: '' },
  label: { type: String, default: '' },
  icon: { type: [String, Object], default: '' },
  expandable: { type: Boolean, default: false },
  isExpanded: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  hasActiveChild: { type: Boolean, default: false },
  getterKeys: { type: Object, default: () => ({}) },
  badgeVariant: { type: String, default: 'default' },
});

const emit = defineEmits(['toggle']);

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
</script>

<template>
  <component
    :is="to ? 'router-link' : 'div'"
    class="flex items-center gap-2 px-1.5 py-1 rounded-lg h-8 min-w-0"
    role="button"
    draggable="false"
    :to="to"
    :title="label"
    :class="{
      'text-n-slate-12 bg-n-alpha-2 font-medium': isActive && !hasActiveChild,
      'text-n-slate-12 font-medium': hasActiveChild,
      'text-n-slate-11 hover:bg-n-alpha-2': !isActive && !hasActiveChild,
    }"
    @click.stop="emit('toggle')"
  >
    <div v-if="icon" class="relative flex items-center gap-2">
      <Icon v-if="icon" :icon="icon" class="size-4" />
      <span
        v-if="showBadge"
        class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2"
      />
    </div>
    <div
      class="flex items-center gap-1.5 flex-grow justify-between min-w-0 flex-1"
    >
      <span
        class="truncate"
        :class="{
          'text-body-main': !isActive,
          'font-medium text-sm': isActive || hasActiveChild,
        }"
      >
        {{ label }}
      </span>
      <SidebarUnreadBadge
        v-if="!expandable"
        :count="dynamicCount"
        :variant="badgeVariant"
      />
    </div>
    <span
      v-if="expandable"
      v-show="isExpanded"
      class="i-lucide-chevron-up size-3"
      @click.stop="emit('toggle')"
    />
  </component>
</template>
