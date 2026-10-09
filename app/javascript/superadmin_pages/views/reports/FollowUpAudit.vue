<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const PERIODS = [
  { value: '24h', label: 'Últimas 24 horas' },
  { value: '7d', label: 'Últimos 7 dias' },
  { value: '30d', label: 'Últimos 30 dias' },
];
const DELIVERIES = [
  { value: '', label: 'Todos' },
  { value: 'sent', label: 'Enviados' },
  { value: 'failed', label: 'Com erro' },
  { value: 'pending', label: 'Pendentes' },
];

const filters = ref({ period: '24h', account_id: '', delivery: '' });
const totals = ref({});
const accounts = ref([]);
const issues = ref([]);
const loading = ref(false);
const error = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const url = new URL(props.componentData.data_url, window.location.origin);
    Object.entries(filters.value).forEach(([key, value]) => {
      if (value) url.searchParams.set(key, value);
    });
    const res = await fetch(url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const body = await res.json();
    totals.value = body.totals || {};
    accounts.value = body.accounts || [];
    issues.value = body.issues || [];
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

const percent = (part, whole) =>
  whole ? `${((part / whole) * 100).toFixed(1).replace('.', ',')}%` : '0%';

const seconds = value =>
  value == null ? '—' : `${String(value).replace('.', ',')} s`;

const delayLabel = minutes => {
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const rest = minutes % 60;
  if (days) return hours ? `${days}d ${hours}h` : `${days}d`;
  if (hours) return rest ? `${hours}h${rest}min` : `${hours}h`;
  return `${rest}min`;
};

const dateTime = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

const conversationUrl = row =>
  `/app/accounts/${row.account_id}/conversations/${row.conversation_id}`;

const accountOptions = computed(() =>
  accounts.value.map(row => ({ id: row.account_id, name: row.account_name }))
);

const pendingFor = row => {
  const minutes = Math.round((Date.now() - new Date(row.created_at)) / 60000);
  return minutes >= 60
    ? `há ${Math.floor(minutes / 60)}h${minutes % 60}min`
    : `há ${minutes} min`;
};
</script>

<template>
  <div class="overflow-auto bg-n-background w-full px-6">
    <div class="max-w-7xl mx-auto pb-12">
      <header class="flex flex-wrap items-end justify-between gap-4 pt-6 pb-5">
        <div>
          <h1 class="text-heading-1 text-n-slate-12">Auditoria de FUP</h1>
          <p class="text-sm text-n-slate-11 mt-1">
            Processamento dos follow-ups de todas as contas: quando começaram,
            quanto levaram e o que falhou.
          </p>
        </div>
        <div class="flex flex-wrap items-end gap-3">
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            Período
            <select
              v-model="filters.period"
              class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
              @change="fetchData"
            >
              <option v-for="p in PERIODS" :key="p.value" :value="p.value">
                {{ p.label }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            Conta
            <select
              v-model="filters.account_id"
              class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
              @change="fetchData"
            >
              <option value="">Todas as contas</option>
              <option v-for="a in accountOptions" :key="a.id" :value="a.id">
                #{{ a.id }} {{ a.name }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            Envio
            <select
              v-model="filters.delivery"
              class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
              @change="fetchData"
            >
              <option v-for="d in DELIVERIES" :key="d.value" :value="d.value">
                {{ d.label }}
              </option>
            </select>
          </label>
          <button
            type="button"
            class="h-9 px-3 rounded-lg text-sm font-medium text-white bg-n-brand hover:bg-n-brand/90 disabled:opacity-50"
            :disabled="loading"
            @click="fetchData"
          >
            {{ loading ? 'Atualizando…' : 'Atualizar' }}
          </button>
        </div>
      </header>

      <div
        v-if="error"
        class="px-4 py-3 mb-4 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
      >
        Falha ao carregar dados: {{ error }}
      </div>

      <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">FUPs processados</div>
          <div class="text-3xl font-medium text-n-slate-12 mt-2">
            {{ totals.total ?? 0 }}
          </div>
          <div class="text-xs text-n-slate-11 mt-1">
            em {{ totals.accounts ?? 0 }} contas
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">Erros de envio</div>
          <div class="text-3xl font-medium text-n-ruby-11 mt-2">
            {{ totals.failed ?? 0 }}
            <span class="text-sm">{{
              percent(totals.failed, totals.total)
            }}</span>
          </div>
          <div class="text-xs text-n-slate-11 mt-1">template ou conexão</div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">
            Tempo médio de processamento
          </div>
          <div class="text-3xl font-medium text-n-slate-12 mt-2">
            {{ seconds(totals.avg_seconds) }}
          </div>
          <div class="text-xs text-n-slate-11 mt-1">
            do início ao envio · maior: {{ seconds(totals.max_seconds) }}
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">Pendentes há mais de 5 min</div>
          <div class="text-3xl font-medium text-n-amber-11 mt-2">
            {{ totals.stuck ?? 0 }}
          </div>
          <div class="text-xs text-n-slate-11 mt-1">
            começaram e não confirmaram o envio
          </div>
        </div>
        <div
          class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-5 py-4"
        >
          <div class="text-sm text-n-slate-11">Reengajamento geral</div>
          <div class="text-3xl font-medium text-n-teal-11 mt-2">
            {{ percent(totals.reengaged_conversations, totals.conversations) }}
          </div>
          <div class="text-xs text-n-slate-11 mt-1">
            {{ totals.reengaged_conversations ?? 0 }} de
            {{ totals.conversations ?? 0 }} conversas
          </div>
        </div>
      </div>

      <section
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow mb-6"
      >
        <h2 class="px-5 py-3 text-base font-medium text-n-slate-12">
          Por conta
        </h2>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-n-slate-1 text-n-slate-12">
              <tr>
                <th class="text-left px-5 py-3 font-medium">Conta</th>
                <th class="text-left px-5 py-3 font-medium">Config. de FUP</th>
                <th class="text-left px-5 py-3 font-medium">Processados</th>
                <th class="text-left px-5 py-3 font-medium">Erros</th>
                <th class="text-left px-5 py-3 font-medium">Tempo médio</th>
                <th class="text-left px-5 py-3 font-medium">Último FUP</th>
                <th class="text-left px-5 py-3 font-medium">Reengajamento</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-slate-2">
              <tr
                v-for="row in accounts"
                :key="row.account_id"
                class="text-n-slate-12"
              >
                <td class="px-5 py-3">
                  <a
                    :href="`/super_admin/accounts/${row.account_id}`"
                    class="text-n-brand hover:underline"
                  >
                    #{{ row.account_id }} {{ row.account_name }}
                  </a>
                </td>
                <td class="px-5 py-3 text-n-slate-11 whitespace-nowrap">
                  {{
                    row.steps.length
                      ? row.steps.map(delayLabel).join(' → ')
                      : '—'
                  }}
                </td>
                <td class="px-5 py-3">{{ row.total }}</td>
                <td class="px-5 py-3">
                  <span
                    class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                    :class="
                      row.failed
                        ? 'bg-n-ruby-3 text-n-ruby-11'
                        : 'bg-n-alpha-2 text-n-slate-11'
                    "
                  >
                    {{ row.failed }}
                  </span>
                </td>
                <td class="px-5 py-3">{{ seconds(row.avg_seconds) }}</td>
                <td class="px-5 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ dateTime(row.last_at) }}
                </td>
                <td class="px-5 py-3 font-semibold">
                  {{ percent(row.reengaged_conversations, row.conversations) }}
                </td>
              </tr>
              <tr v-if="!accounts.length && !loading">
                <td colspan="7" class="px-5 py-8 text-center text-n-slate-11">
                  Nenhum follow-up no período.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow"
      >
        <h2 class="px-5 py-3 text-base font-medium text-n-slate-12">
          Erros e pendências
        </h2>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-n-slate-1 text-n-slate-12">
              <tr>
                <th class="text-left px-5 py-3 font-medium">Início</th>
                <th class="text-left px-5 py-3 font-medium">Conta</th>
                <th class="text-left px-5 py-3 font-medium">Conversa</th>
                <th class="text-left px-5 py-3 font-medium">FUP</th>
                <th class="text-left px-5 py-3 font-medium">Execução</th>
                <th class="text-left px-5 py-3 font-medium">Duração</th>
                <th class="text-left px-5 py-3 font-medium">Situação</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-slate-2">
              <tr
                v-for="row in issues"
                :key="row.id"
                class="text-n-slate-12 align-top"
              >
                <td class="px-5 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ dateTime(row.created_at) }}
                </td>
                <td class="px-5 py-3">
                  #{{ row.account_id }} {{ row.account_name }}
                </td>
                <td class="px-5 py-3">
                  <a
                    :href="conversationUrl(row)"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-n-brand hover:underline font-mono"
                  >
                    #{{ row.conversation_id }}
                  </a>
                </td>
                <td class="px-5 py-3 whitespace-nowrap">
                  FUP {{ row.step }} · {{ delayLabel(row.delay_minutes) }}
                </td>
                <td class="px-5 py-3 font-mono text-xs text-n-slate-11">
                  {{ row.run_id }}
                </td>
                <td class="px-5 py-3 whitespace-nowrap">
                  {{
                    row.delivery_status === 'pending'
                      ? pendingFor(row)
                      : seconds(row.duration_seconds)
                  }}
                </td>
                <td class="px-5 py-3">
                  <span
                    class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                    :class="
                      row.delivery_status === 'failed'
                        ? 'bg-n-ruby-3 text-n-ruby-11'
                        : 'bg-n-amber-3 text-n-amber-11'
                    "
                  >
                    {{ row.delivery_status === 'failed' ? 'Erro' : 'Pendente' }}
                  </span>
                  <div class="text-xs text-n-slate-11 mt-1">
                    {{ row.error_message || 'Começou e não confirmou o envio' }}
                  </div>
                </td>
              </tr>
              <tr v-if="!issues.length && !loading">
                <td colspan="7" class="px-5 py-8 text-center text-n-slate-11">
                  Nenhum erro ou pendência no período.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>
