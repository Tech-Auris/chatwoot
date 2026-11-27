<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { CALL_MS, callsAt } from '../engine/livePieces';

// The sala de espera call screen, big: the ticket called now, the ones
// before it and a ticker. The tickets are made up (see livePieces.js), the
// same ones the TV on the map shows.
const props = defineProps({
  timeZone: { type: String, required: true },
});
const emit = defineEmits(['close']);

const { t, locale } = useI18n();
const { currentAccount } = useAccount();
const dialog = ref(null);
const now = ref(Date.now());
let timer = null;

const calls = computed(() => callsAt(now.value, 7));
const current = computed(() => calls.value[0]);
// On the map a ticket is called every few seconds, to keep the room alive;
// here the earlier ones read like a real afternoon, a few minutes apart.
const GAP_MS = 3 * 60 * 1000;
const history = computed(() =>
  calls.value
    .slice(1)
    .map((call, i) => ({ ...call, at: current.value.at - (i + 1) * GAP_MS }))
);
// The ticket blinks for a moment when it is called.
const calling = computed(() => now.value % CALL_MS < 1500);

const hourFormat = computed(
  () =>
    // The app names locales like "pt_BR"; Intl wants "pt-BR".
    new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
      timeZone: props.timeZone,
      hour: '2-digit',
      minute: '2-digit',
    })
);
const timeOf = at => hourFormat.value.format(new Date(at));

onMounted(() => {
  dialog.value.open();
  timer = setInterval(() => {
    now.value = Date.now();
  }, 500);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="t('VIRTUAL_CLINIC.CALL_SCREEN.TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="t('VIRTUAL_CLINIC.CALL_SCREEN.CLOSE')"
    @close="emit('close')"
  >
    <div
      class="flex flex-col overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="grid grid-cols-5">
        <div
          class="flex flex-col col-span-3 gap-1 p-6 text-white transition-colors"
          :class="calling ? 'bg-n-teal-9' : 'bg-n-brand'"
        >
          <span class="text-xs opacity-80">{{ currentAccount?.name }}</span>
          <span class="mt-2 text-sm font-medium uppercase">
            {{ t('VIRTUAL_CLINIC.CALL_SCREEN.TICKET') }}
          </span>
          <span class="font-mono text-6xl font-bold tracking-wider">
            {{ current.ticket }}
          </span>
          <span class="mt-4 text-sm font-medium uppercase">
            {{ t('VIRTUAL_CLINIC.CALL_SCREEN.ROOM') }}
          </span>
          <span class="text-5xl font-bold">{{ current.room }}</span>
        </div>
        <div
          class="flex flex-col items-center justify-center col-span-2 gap-2 p-6 text-center bg-n-alpha-1"
        >
          <span class="text-4xl font-semibold tabular-nums text-n-slate-12">
            {{ timeOf(now) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t('VIRTUAL_CLINIC.CALL_SCREEN.WAIT') }}
          </span>
        </div>
      </div>
      <div class="px-6 py-4">
        <p class="mb-2 text-sm font-semibold text-n-slate-12">
          {{ t('VIRTUAL_CLINIC.CALL_SCREEN.HISTORY') }}
        </p>
        <table class="w-full text-sm text-left">
          <thead class="text-xs text-n-slate-11">
            <tr>
              <th class="py-1 font-medium">
                {{ t('VIRTUAL_CLINIC.CALL_SCREEN.TICKET') }}
              </th>
              <th class="py-1 font-medium">
                {{ t('VIRTUAL_CLINIC.CALL_SCREEN.ROOM') }}
              </th>
              <th class="py-1 font-medium">
                {{ t('VIRTUAL_CLINIC.CALL_SCREEN.TIME') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="call in history"
              :key="call.index"
              class="border-t border-n-weak text-n-slate-12"
            >
              <td class="py-1 font-mono">{{ call.ticket }}</td>
              <td class="py-1">{{ call.room }}</td>
              <td class="py-1 tabular-nums">{{ timeOf(call.at) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="overflow-hidden py-1.5 text-sm text-white bg-n-brand">
        <p class="inline-block pl-[100%] whitespace-nowrap animate-marquee">
          {{
            t('VIRTUAL_CLINIC.CALL_SCREEN.TICKER', {
              clinic: currentAccount?.name,
            })
          }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
