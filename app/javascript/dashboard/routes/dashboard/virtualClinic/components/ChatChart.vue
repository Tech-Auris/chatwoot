<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { Bar, Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  BarElement,
  CategoryScale,
  Legend,
  LinearScale,
  LineElement,
  PointElement,
  Tooltip,
} from 'chart.js';

// A chart the manager drew in her answer (render_chart): `{ type, title,
// labels, series: [{ name, data }] }`, with the numbers under "ver dados".
const props = defineProps({
  chart: { type: Object, required: true },
});

ChartJS.register(
  BarElement,
  CategoryScale,
  Legend,
  LinearScale,
  LineElement,
  PointElement,
  Tooltip
);

const { t } = useI18n();
const showData = ref(false);

// chart.js needs plain colors: blue, iris, teal and amber of the palette.
const COLORS = ['#2563eb', '#6e56cf', '#12a594', '#e2a336'];

const data = computed(() => ({
  labels: props.chart.labels,
  datasets: props.chart.series.map((serie, index) => ({
    label: serie.name,
    data: serie.data,
    backgroundColor: COLORS[index % COLORS.length],
    borderColor: COLORS[index % COLORS.length],
    tension: 0.3,
  })),
}));

const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 0 },
  plugins: { legend: { display: props.chart.series.length > 1 } },
  scales: { y: { beginAtZero: true } },
}));
</script>

<template>
  <figure class="flex flex-col gap-2 p-2 mt-2 rounded-xl bg-n-solid-1">
    <figcaption class="text-xs font-medium text-n-slate-12">
      {{ chart.title }}
    </figcaption>
    <div class="h-44">
      <Bar v-if="chart.type === 'bar'" :data="data" :options="options" />
      <Line v-else :data="data" :options="options" />
    </div>
    <button
      type="button"
      class="self-start text-xs font-medium underline text-n-slate-11"
      @click="showData = !showData"
    >
      {{
        showData
          ? t('VIRTUAL_CLINIC.CHAT.HIDE_DATA')
          : t('VIRTUAL_CLINIC.CHAT.SHOW_DATA')
      }}
    </button>
    <table v-if="showData" class="w-full text-xs">
      <thead>
        <tr class="text-left text-n-slate-11">
          <th class="py-0.5 pr-2" />
          <th
            v-for="serie in chart.series"
            :key="serie.name"
            class="py-0.5 pr-2"
          >
            {{ serie.name }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="(label, index) in chart.labels"
          :key="label"
          class="border-t border-n-weak"
        >
          <td class="py-0.5 pr-2 text-n-slate-11">{{ label }}</td>
          <td
            v-for="serie in chart.series"
            :key="serie.name"
            class="py-0.5 pr-2 text-n-slate-12"
          >
            {{ serie.data[index] }}
          </td>
        </tr>
      </tbody>
    </table>
  </figure>
</template>
