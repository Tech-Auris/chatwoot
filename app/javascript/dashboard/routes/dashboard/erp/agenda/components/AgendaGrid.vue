<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { layoutColumn, hourRange } from '../agendaLayout';

// A time grid with one column per professional (day view) or per day (week
// view). Each column brings its own appointments, already filtered.
const props = defineProps({
  columns: { type: Array, required: true },
  showProfessional: { type: Boolean, default: false },
  locale: { type: String, default: 'en' },
});

const emit = defineEmits(['select']);
const { t } = useI18n();
const route = useRoute();

// The badge of the appointments the AI booked opens the patient conversation.
const conversationRoute = conversationId => ({
  name: 'inbox_conversation',
  params: { accountId: route.params.accountId, conversation_id: conversationId },
});

// Tall enough for a 30-minute appointment to show its two lines.
const HOUR_HEIGHT = 96;

const hours = computed(() =>
  hourRange(props.columns.flatMap(column => column.appointments))
);
const hourLabels = computed(() =>
  Array.from(
    { length: hours.value.end - hours.value.start },
    (_, i) => `${String(hours.value.start + i).padStart(2, '0')}:00`
  )
);
const gridHeight = computed(
  () => (hours.value.end - hours.value.start) * HOUR_HEIGHT
);

const placedColumns = computed(() =>
  props.columns.map(column => ({
    ...column,
    placed: layoutColumn(column.appointments),
  }))
);

const toPixels = minutes =>
  ((minutes - hours.value.start * 60) * HOUR_HEIGHT) / 60;

const cardStyle = item => ({
  top: `${toPixels(item.start)}px`,
  height: `${((item.end - item.start) * HOUR_HEIGHT) / 60 - 2}px`,
  left: `${(item.lane / item.lanes) * 100}%`,
  width: `calc(${100 / item.lanes}% - 4px)`,
});

const STATUS_CLASS = {
  scheduled: 'bg-n-teal-3 border-n-teal-9 text-n-teal-12',
  confirmed: 'bg-n-blue-3 border-n-blue-9 text-n-blue-12',
  rescheduled: 'bg-n-amber-3 border-n-amber-9 text-n-amber-12',
  waiting: 'bg-n-violet-3 border-n-violet-9 text-n-violet-12',
  in_progress: 'bg-n-iris-3 border-n-iris-9 text-n-iris-12',
  attended: 'bg-n-slate-3 border-n-slate-9 text-n-slate-12',
  no_show: 'bg-n-ruby-3 border-n-ruby-9 text-n-ruby-12',
  canceled: 'bg-n-slate-2 border-n-slate-6 text-n-slate-10 line-through',
};

const formatTime = value =>
  new Intl.DateTimeFormat(props.locale, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));

const statusLabel = status => t(`AGENDA.STATUS.${status.toUpperCase()}`);

const cardTitle = appointment =>
  [
    `${formatTime(appointment.starts_at)} · ${statusLabel(appointment.status)}`,
    appointment.patient_name,
    appointment.procedure_name,
    appointment.professional_name,
  ]
    .filter(Boolean)
    .join('\n');
</script>

<template>
  <div class="flex min-w-max">
    <div class="sticky left-0 z-10 w-16 shrink-0 bg-n-solid-1">
      <div class="h-12 border-b border-n-weak" />
      <div
        v-for="label in hourLabels"
        :key="label"
        class="h-24 pr-2 text-xs text-right -translate-y-2 text-n-slate-10"
      >
        {{ label }}
      </div>
    </div>
    <div
      v-for="column in placedColumns"
      :key="column.key"
      class="flex flex-col flex-1 min-w-48 border-l border-n-weak"
    >
      <div
        class="sticky top-0 z-10 flex flex-col justify-center h-12 px-3 border-b border-n-weak bg-n-solid-1"
      >
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ column.label }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            $t('AGENDA.APPOINTMENTS_COUNT', {
              count: column.appointments.length,
            })
          }}
        </span>
      </div>
      <div class="relative" :style="{ height: `${gridHeight}px` }">
        <div
          v-for="label in hourLabels"
          :key="label"
          class="h-24 border-b border-n-weak border-dashed"
        />
        <div
          v-for="item in column.placed"
          :key="item.appointment.id"
          role="button"
          tabindex="0"
          :title="cardTitle(item.appointment)"
          class="absolute flex flex-col px-2 py-0.5 mx-0.5 overflow-hidden text-xs text-left border-l-4 rounded-md cursor-pointer hover:brightness-95"
          :class="STATUS_CLASS[item.appointment.status]"
          :style="cardStyle(item)"
          @click="emit('select', item.appointment)"
          @keydown.enter="emit('select', item.appointment)"
        >
          <div class="flex items-center gap-1 font-semibold">
            <span class="truncate">
              {{ formatTime(item.appointment.starts_at) }}
              {{ item.appointment.patient_name }}
            </span>
            <router-link
              v-if="item.appointment.auris_conversation_id"
              :to="conversationRoute(item.appointment.auris_conversation_id)"
              :title="t('AGENDA.AURIS.OPEN_CONVERSATION')"
              class="px-1 ml-auto font-semibold no-underline rounded shrink-0 text-[10px] leading-4 bg-n-brand text-white hover:opacity-90"
              @click.stop
            >
              {{ t('AGENDA.AURIS.BADGE') }}
            </router-link>
          </div>
          <div v-if="item.appointment.procedure_name" class="truncate">
            {{ item.appointment.procedure_name }}
          </div>
          <div
            v-if="showProfessional && item.appointment.professional_name"
            class="truncate opacity-80"
          >
            {{ item.appointment.professional_name }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
