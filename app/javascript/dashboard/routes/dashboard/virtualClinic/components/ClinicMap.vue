<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { CHARACTERS, ROOMS, SPRITE_PATHS, WORLD } from '../engine/layout';
import { loadSprites } from '../engine/sprites';
import { createRenderer, hitTest } from '../engine/renderer';

const props = defineProps({
  aiTeam: { type: Object, default: null },
  status: { type: Object, default: null },
  thinking: { type: String, default: '' },
});
const emit = defineEmits(['selectMember']);

const { t } = useI18n();
const FRAME_MS = 160;
const ROTATE_MS = 10000;

const viewport = ref(null);
const canvas = ref(null);
const loading = ref(true);
const failed = ref(false);
const scale = ref(1);
const tick = ref(0);
const rotation = ref(0);
let draw = null;
let frameTimer = null;
let rotateTimer = null;
let resizeObserver = null;

const members = computed(() =>
  props.aiTeam?.visible ? props.aiTeam.members : []
);
const enabled = computed(() => props.aiTeam?.enabled === true);
const secretaryBusy = computed(
  () => (props.status?.secretary?.active_conversations || 0) > 0
);

const characters = computed(() =>
  members.value.map(member => ({
    persona: member.persona,
    animation:
      member.persona === 'secretary' && secretaryBusy.value ? 'phone' : 'idle',
    faded: !enabled.value,
  }))
);

// What each teammate is doing, over their head.
const bubble = persona => {
  if (!enabled.value) return '';
  if (props.thinking === persona) return t('VIRTUAL_CLINIC.MAP.THINKING');
  if (!props.status) return '';
  if (persona === 'secretary') {
    const { active_conversations: active, in_follow_up: followUps } =
      props.status.secretary;
    return active || followUps
      ? t('VIRTUAL_CLINIC.MAP.SECRETARY', { active, followUps })
      : t('VIRTUAL_CLINIC.MAP.IDLE');
  }
  const {
    leads,
    appointments,
    conversion_rate: rate,
  } = props.status.manager.month;
  const lines = [
    t('VIRTUAL_CLINIC.MAP.LEADS', { leads }),
    t('VIRTUAL_CLINIC.MAP.APPOINTMENTS', { appointments }),
    ...(rate === null ? [] : [t('VIRTUAL_CLINIC.MAP.CONVERSION', { rate })]),
  ];
  return lines[rotation.value % lines.length];
};

const at = point => ({
  left: `${point.x * scale.value}px`,
  top: `${point.y * scale.value}px`,
});
const worldSize = computed(() => ({
  width: `${WORLD.width * scale.value}px`,
  height: `${WORLD.height * scale.value}px`,
}));

const render = () => draw?.(characters.value, tick.value);
watch([characters, tick], render);

const animate = () => {
  if (!document.hidden) tick.value += 1;
};

// Integer zoom only, so the pixel art stays sharp.
const fit = () => {
  const width = viewport.value?.clientWidth || WORLD.width;
  scale.value = Math.max(1, Math.floor(width / WORLD.width));
};
const zoom = step => {
  scale.value = Math.min(3, Math.max(1, scale.value + step));
};

const onClick = event => {
  const rect = canvas.value.getBoundingClientRect();
  const persona = hitTest(
    (event.clientX - rect.left) / scale.value,
    (event.clientY - rect.top) / scale.value,
    members.value.map(member => member.persona)
  );
  if (persona && enabled.value) emit('selectMember', persona);
};

// Drag the map around when it is bigger than the screen.
let drag = null;
const startDrag = event => {
  drag = {
    x: event.clientX,
    y: event.clientY,
    left: viewport.value.scrollLeft,
    top: viewport.value.scrollTop,
  };
};
const moveDrag = event => {
  if (!drag) return;
  viewport.value.scrollLeft = drag.left - (event.clientX - drag.x);
  viewport.value.scrollTop = drag.top - (event.clientY - drag.y);
};
const endDrag = () => {
  drag = null;
};

onMounted(async () => {
  fit();
  resizeObserver = new ResizeObserver(fit);
  resizeObserver.observe(viewport.value);
  try {
    const sprites = await loadSprites(SPRITE_PATHS, path =>
      VirtualClinicAPI.getAsset(path)
    );
    draw = createRenderer(canvas.value, sprites);
    render();
    frameTimer = setInterval(animate, FRAME_MS);
    rotateTimer = setInterval(() => {
      rotation.value += 1;
    }, ROTATE_MS);
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
});

onBeforeUnmount(() => {
  clearInterval(frameTimer);
  clearInterval(rotateTimer);
  resizeObserver?.disconnect();
});
</script>

<template>
  <div class="relative flex-1 min-w-0 overflow-hidden bg-n-alpha-1">
    <div class="absolute z-10 flex gap-1 top-3 right-3">
      <Button
        icon="i-lucide-minus"
        size="xs"
        color="slate"
        :disabled="scale === 1"
        @click="zoom(-1)"
      />
      <Button
        icon="i-lucide-plus"
        size="xs"
        color="slate"
        :disabled="scale === 3"
        @click="zoom(1)"
      />
    </div>
    <div
      ref="viewport"
      class="w-full h-full overflow-auto cursor-grab active:cursor-grabbing"
      @mousedown="startDrag"
      @mousemove="moveDrag"
      @mouseup="endDrag"
      @mouseleave="endDrag"
    >
      <div class="relative mx-auto my-4" :style="worldSize">
        <canvas
          ref="canvas"
          :width="WORLD.width"
          :height="WORLD.height"
          class="block w-full h-full [image-rendering:pixelated]"
          @click="onClick"
        />
        <template v-if="!loading && !failed">
          <span
            v-for="room in ROOMS"
            :key="room.key"
            class="absolute px-2 py-0.5 text-xs font-semibold text-white rounded-md pointer-events-none bg-n-slate-12/80"
            :style="at(room)"
          >
            {{ t(`VIRTUAL_CLINIC.MAP.ROOMS.${room.key}`) }}
          </span>
          <template v-for="member in members" :key="member.persona">
            <span
              v-if="bubble(member.persona)"
              class="absolute px-2 py-1 text-xs font-medium -translate-x-1/2 -translate-y-full bg-white rounded-lg shadow-md pointer-events-none whitespace-nowrap text-n-slate-12"
              :style="at(CHARACTERS[member.persona].bubble)"
            >
              {{ bubble(member.persona) }}
            </span>
            <button
              type="button"
              class="absolute px-2 py-0.5 text-xs font-semibold text-white -translate-x-1/2 rounded-full shadow whitespace-nowrap"
              :class="[
                member.persona === 'secretary' ? 'bg-n-blue-9' : 'bg-n-iris-9',
                enabled ? '' : 'opacity-50 cursor-default',
              ]"
              :style="at(CHARACTERS[member.persona].tag)"
              @click="enabled && emit('selectMember', member.persona)"
            >
              {{ member.name }} ·
              {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
            </button>
          </template>
        </template>
      </div>
    </div>
    <div
      v-if="loading || failed"
      class="absolute inset-0 grid place-items-center text-sm text-n-slate-11"
    >
      <Spinner v-if="loading" />
      <span v-else>{{ t('VIRTUAL_CLINIC.MAP.LOAD_ERROR') }}</span>
    </div>
  </div>
</template>
