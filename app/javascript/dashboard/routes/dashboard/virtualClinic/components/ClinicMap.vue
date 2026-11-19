<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VirtualClinicAPI from 'dashboard/api/virtualClinic';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { CHARACTERS, ROOMS, SPRITE_PATHS, WORLD } from '../engine/layout';
import { loadSprites } from '../engine/sprites';
import { createRenderer, hitTest } from '../engine/renderer';
import { createTeamBehavior } from '../engine/behavior';
import { isOffDuty, offDutyReason } from '../teamStatus';

const props = defineProps({
  aiTeam: { type: Object, default: null },
  status: { type: Object, default: null },
  thinking: { type: String, default: '' },
  focused: { type: String, default: '' },
});
const emit = defineEmits(['selectMember']);

const { t } = useI18n();
const FRAME_MS = 100;
const ROTATE_MS = 10000;

const viewport = ref(null);
const canvas = ref(null);
const loading = ref(true);
const failed = ref(false);
const scale = ref(1);
const fitScale = ref(1);
const userZoomed = ref(false);
const MAX_SCALE = 4;
const minScale = computed(() => Math.min(1, fitScale.value * 0.75));
const tick = ref(0);
const rotation = ref(0);
let draw = null;
let behavior = null;
const positions = ref({});
let frameTimer = null;
let rotateTimer = null;
let resizeObserver = null;

const members = computed(() =>
  props.aiTeam?.visible ? props.aiTeam.members : []
);
// Talking to them needs the clinic's OpenAI key; Clara is only faded when
// she is not serving patients (the n8n secretary), which is another switch.
const chatEnabled = computed(() => props.aiTeam?.chat_enabled === true);
const secretaryBusy = computed(
  () => (props.status?.secretary?.active_conversations || 0) > 0
);

// Where each teammate is now (they take little walks, see engine/trips.js).
const placeOf = persona => {
  const spot = CHARACTERS[persona];
  return positions.value[persona] || { x: spot.x, y: spot.y };
};

const characters = computed(() =>
  members.value.map(member => {
    const place = placeOf(member.persona);
    return {
      persona: member.persona,
      x: place.x,
      y: place.y,
      direction: place.direction || 'down',
      moving: place.moving,
      talking: place.talking,
      phone:
        member.persona === 'secretary' && secretaryBusy.value && !place.away,
      faded: isOffDuty(member.persona, props.status),
    };
  })
);

// Name (and status above it) sit right over the head, like in Gather, and
// follow the teammate around. The frame is 32×64 with the head from ~y+18.
const overHead = persona => {
  const place = placeOf(persona);
  return { x: place.x + 16, y: place.y + 18 };
};

// Nobody leaves while the user talks to them or when off duty.
const canLeave = persona =>
  persona !== props.focused &&
  persona !== props.thinking &&
  !isOffDuty(persona, props.status);

watch(
  () => members.value.map(member => member.persona).join(),
  personaList => {
    behavior = personaList
      ? createTeamBehavior({ personas: personaList.split(','), canLeave })
      : null;
    positions.value = {};
  },
  { immediate: true }
);

// What each teammate is doing, over their head (hidden while away).
const bubble = persona => {
  if (props.thinking === persona) return t('VIRTUAL_CLINIC.MAP.THINKING');
  if (placeOf(persona).away) return '';
  if (!props.status) return '';
  if (isOffDuty(persona, props.status)) {
    return t('VIRTUAL_CLINIC.MAP.OFF_DUTY', {
      reason: offDutyReason(props.status, t),
    });
  }
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
  if (document.hidden) return;
  if (behavior) {
    behavior.update(performance.now());
    positions.value = Object.fromEntries(
      Object.entries(behavior.state).map(([persona, place]) => [
        persona,
        { ...place },
      ])
    );
  }
  tick.value += 1;
};

// The map fills the area by default; the user can zoom in and out from
// there (wheel or the +/- control), like in Gather.
const fit = () => {
  const width = viewport.value?.clientWidth || WORLD.width;
  const height = viewport.value?.clientHeight || WORLD.height;
  fitScale.value = Math.min(width / WORLD.width, height / WORLD.height);
  if (!userZoomed.value) scale.value = fitScale.value;
};

// Keeps the point under the cursor (or the center) in place while zooming.
const zoomTo = (next, anchor) => {
  const target = Math.min(MAX_SCALE, Math.max(minScale.value, next));
  const box = viewport.value;
  const rect = box.getBoundingClientRect();
  const point = anchor || {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
  const worldX = (box.scrollLeft + point.x - rect.left) / scale.value;
  const worldY = (box.scrollTop + point.y - rect.top) / scale.value;
  userZoomed.value = true;
  scale.value = target;
  requestAnimationFrame(() => {
    box.scrollLeft = worldX * target - (point.x - rect.left);
    box.scrollTop = worldY * target - (point.y - rect.top);
  });
};
const zoom = factor => zoomTo(scale.value * factor);
const onWheel = event => {
  zoomTo(scale.value * (event.deltaY < 0 ? 1.1 : 1 / 1.1), {
    x: event.clientX,
    y: event.clientY,
  });
};
const resetZoom = () => {
  userZoomed.value = false;
  scale.value = fitScale.value;
};

const onClick = event => {
  const rect = canvas.value.getBoundingClientRect();
  const persona = hitTest(
    (event.clientX - rect.left) / scale.value,
    (event.clientY - rect.top) / scale.value,
    characters.value
  );
  if (persona && chatEnabled.value) emit('selectMember', persona);
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
    <div
      class="absolute z-10 flex flex-col overflow-hidden text-white shadow-lg bottom-4 right-4 rounded-xl bg-n-slate-12/90"
    >
      <button
        type="button"
        class="grid size-10 place-items-center hover:bg-white/10 disabled:opacity-40"
        :title="t('VIRTUAL_CLINIC.MAP.ZOOM_IN')"
        :disabled="scale >= MAX_SCALE"
        @click="zoom(1.25)"
      >
        <Icon icon="i-lucide-plus" class="size-5" />
      </button>
      <button
        type="button"
        class="grid size-10 place-items-center hover:bg-white/10"
        :title="t('VIRTUAL_CLINIC.MAP.ZOOM_FIT')"
        @click="resetZoom"
      >
        <Icon icon="i-lucide-scan" class="size-4" />
      </button>
      <button
        type="button"
        class="grid size-10 place-items-center hover:bg-white/10 disabled:opacity-40"
        :title="t('VIRTUAL_CLINIC.MAP.ZOOM_OUT')"
        :disabled="scale <= minScale"
        @click="zoom(0.8)"
      >
        <Icon icon="i-lucide-minus" class="size-5" />
      </button>
    </div>
    <div
      ref="viewport"
      class="flex w-full h-full overflow-auto cursor-grab active:cursor-grabbing"
      @wheel.prevent="onWheel"
      @mousedown="startDrag"
      @mousemove="moveDrag"
      @mouseup="endDrag"
      @mouseleave="endDrag"
    >
      <div class="relative m-auto shrink-0" :style="worldSize">
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
            :class="{ '-translate-x-full': room.alignRight }"
            :style="at(room)"
          >
            {{ t(`VIRTUAL_CLINIC.MAP.ROOMS.${room.key}`) }}
          </span>
          <div
            v-for="member in members"
            :key="member.persona"
            class="absolute flex flex-col items-center gap-1 -translate-x-1/2 -translate-y-full pointer-events-none"
            :style="at(overHead(member.persona))"
          >
            <span
              v-if="bubble(member.persona)"
              class="px-2 py-1 text-xs font-medium bg-white rounded-lg shadow-md whitespace-nowrap text-n-slate-12"
            >
              {{ bubble(member.persona) }}
            </span>
            <button
              type="button"
              class="px-2 py-0.5 text-xs font-semibold text-white rounded-full shadow whitespace-nowrap pointer-events-auto"
              :class="[
                member.persona === 'secretary' ? 'bg-n-blue-9' : 'bg-n-iris-9',
                chatEnabled ? '' : 'cursor-default',
                isOffDuty(member.persona, status) ? 'opacity-50' : '',
              ]"
              @click="chatEnabled && emit('selectMember', member.persona)"
            >
              {{ member.name }} ·
              {{ t(`VIRTUAL_CLINIC.PERSONAS.${member.persona.toUpperCase()}`) }}
            </button>
          </div>
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
