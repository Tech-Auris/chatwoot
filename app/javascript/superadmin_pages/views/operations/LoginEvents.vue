<script setup>
import { ref, onMounted, watch, computed } from 'vue';

const props = defineProps({
  componentData: { type: Object, default: () => ({}) },
});

const ROLE_LABELS = {
  agent: 'Agent',
  administrator: 'Administrator',
  manager: 'Manager',
};

const ROLE_OPTIONS = [
  { id: '', label: 'Todos os perfis' },
  { id: 'administrator', label: 'Administrator' },
  { id: 'manager', label: 'Manager' },
  { id: 'agent', label: 'Agent' },
];

const accountsProp = computed(() => props.componentData.accounts || []);

const events = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const loading = ref(false);
const error = ref(null);

const accountFilter = ref('');
const roleFilter = ref('');
const fromFilter = ref('');
const toFilter = ref('');
const page = ref(1);

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({ page: page.value });
    if (accountFilter.value) params.set('account_id', accountFilter.value);
    if (roleFilter.value) params.set('role', roleFilter.value);
    if (fromFilter.value) params.set('from', fromFilter.value);
    if (toFilter.value) params.set('to', toFilter.value);
    const res = await fetch(`${props.componentData.data_url}?${params}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    events.value = body.events || [];
    meta.value = body.meta || meta.value;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

// Filters reset page to 1 before refetching so the operator never lands
// on an empty page-3 after narrowing.
watch([accountFilter, roleFilter, fromFilter, toFilter], () => {
  page.value = 1;
  fetchData();
});
watch(page, fetchData);

const formatDateTime = value =>
  value ? new Date(value).toLocaleString('pt-BR') : '—';
const roleLabel = role => ROLE_LABELS[role] || '—';
const roleClass = role => {
  if (role === 'administrator') return 'bg-violet-50 text-violet-700';
  if (role === 'manager') return 'bg-sky-50 text-sky-700';
  if (role === 'agent') return 'bg-slate-50 text-slate-700';
  return 'bg-yellow-50 text-yellow-700';
};

const clearFilters = () => {
  accountFilter.value = '';
  roleFilter.value = '';
  fromFilter.value = '';
  toFilter.value = '';
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Login events</h1>
      <p class="text-sm text-slate-500 mt-1">
        Todo login bem-sucedido no dashboard, com IP, dispositivo e o perfil no
        momento da entrada. Uma linha por conta em que o usuário tinha acesso —
        filtre pela conta para ver quem entrou nela.
      </p>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-4 gap-3 mb-4">
      <div>
        <label class="block text-xs text-slate-500 mb-1">Conta</label>
        <select
          v-model="accountFilter"
          class="w-full px-3 py-2 border border-slate-200 rounded text-sm bg-white"
        >
          <option value="">Todas</option>
          <option
            v-for="account in accountsProp"
            :key="account.id"
            :value="account.id"
          >
            {{ account.name }} (#{{ account.id }})
          </option>
        </select>
      </div>
      <div>
        <label class="block text-xs text-slate-500 mb-1">Perfil</label>
        <select
          v-model="roleFilter"
          class="w-full px-3 py-2 border border-slate-200 rounded text-sm bg-white"
        >
          <option
            v-for="option in ROLE_OPTIONS"
            :key="option.id"
            :value="option.id"
          >
            {{ option.label }}
          </option>
        </select>
      </div>
      <div>
        <label class="block text-xs text-slate-500 mb-1">De</label>
        <input
          v-model="fromFilter"
          type="datetime-local"
          class="w-full px-3 py-2 border border-slate-200 rounded text-sm"
        />
      </div>
      <div>
        <label class="block text-xs text-slate-500 mb-1">Até</label>
        <input
          v-model="toFilter"
          type="datetime-local"
          class="w-full px-3 py-2 border border-slate-200 rounded text-sm"
        />
      </div>
    </div>

    <div class="flex items-center justify-between mb-3">
      <button
        type="button"
        class="text-xs text-slate-500 underline"
        @click="clearFilters"
      >
        Limpar filtros
      </button>
      <span class="text-sm text-slate-400">
        {{ meta.total_count }} registro(s)
      </span>
    </div>

    <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
      {{ error }}
    </div>

    <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

    <table v-else class="w-full text-sm">
      <thead>
        <tr class="text-left text-slate-500 border-b border-slate-100">
          <th class="py-2">Quando</th>
          <th class="py-2">Usuário</th>
          <th class="py-2">Conta</th>
          <th class="py-2">Perfil</th>
          <th class="py-2">Origem</th>
          <th class="py-2">Dispositivo</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="event in events"
          :key="event.id"
          class="border-b border-slate-50 align-top"
        >
          <td class="py-3 text-slate-700 whitespace-nowrap">
            {{ formatDateTime(event.created_at) }}
          </td>
          <td class="py-3">
            <div class="text-slate-900">{{ event.user_name || '—' }}</div>
            <div class="text-xs text-slate-400 mt-1">
              {{ event.user_email }}
            </div>
          </td>
          <td class="py-3 text-slate-700">
            <template v-if="event.account_name">
              {{ event.account_name }}
              <div class="text-xs text-slate-400">#{{ event.account_id }}</div>
            </template>
            <span v-else class="text-slate-400">—</span>
          </td>
          <td class="py-3">
            <span
              class="px-2 py-0.5 rounded text-xs"
              :class="roleClass(event.role)"
            >
              {{ roleLabel(event.role) }}
            </span>
          </td>
          <td class="py-3 text-slate-700">
            <div>{{ event.ip_address || '—' }}</div>
            <div
              v-if="event.city || event.country"
              class="text-xs text-slate-400 mt-1"
            >
              {{ [event.city, event.country].filter(Boolean).join(', ') }}
            </div>
          </td>
          <td class="py-3 text-slate-700">
            <div>
              {{ event.browser_name || '—' }} {{ event.browser_version }}
            </div>
            <div class="text-xs text-slate-400 mt-1">
              {{ event.platform_name }}
              <template
                v-if="event.device_name && event.device_name !== 'Unknown'"
              >
                · {{ event.device_name }}
              </template>
            </div>
          </td>
        </tr>
        <tr v-if="!events.length">
          <td colspan="6" class="py-6 text-center text-slate-400">
            Nenhum login encontrado com os filtros atuais.
          </td>
        </tr>
      </tbody>
    </table>

    <div
      v-if="meta.total_pages > 1"
      class="flex items-center justify-end gap-3 mt-4 text-sm"
    >
      <button
        type="button"
        class="px-2 py-1 rounded border border-slate-200 disabled:opacity-40"
        :disabled="page <= 1"
        @click="page -= 1"
      >
        Anterior
      </button>
      <span class="text-slate-500">
        {{ meta.current_page }} / {{ meta.total_pages }}
      </span>
      <button
        type="button"
        class="px-2 py-1 rounded border border-slate-200 disabled:opacity-40"
        :disabled="page >= meta.total_pages"
        @click="page += 1"
      >
        Próxima
      </button>
    </div>
  </div>
</template>
