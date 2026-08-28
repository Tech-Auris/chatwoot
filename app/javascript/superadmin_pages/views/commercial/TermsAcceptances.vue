<script setup>
import { ref, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const STATUS_LABELS = {
  pending: 'Aguardando assinatura',
  signed: 'Assinado',
  cancelled: 'Cancelado',
};

const TABS = [
  { id: 'signed', label: 'Assinados' },
  { id: 'pending', label: 'Aguardando' },
  { id: '', label: 'Todos' },
];

const acceptances = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const activeTab = ref('signed');
const page = ref(1);
const loading = ref(false);
const error = ref(null);

const openAcceptance = ref(null);
const openContent = ref('');
const loadingContent = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({ page: page.value });
    if (activeTab.value) params.set('status', activeTab.value);

    const res = await fetch(`${props.componentData.data_url}?${params}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    acceptances.value = body.acceptances || [];
    meta.value = body.meta || meta.value;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

watch([activeTab, page], fetchData);

const changeTab = tab => {
  if (activeTab.value === tab) return;
  page.value = 1;
  activeTab.value = tab;
};

const formatDateTime = value =>
  value ? new Date(value).toLocaleString('pt-BR') : '—';

const statusLabel = status => STATUS_LABELS[status] || status;

const statusClass = status => {
  if (status === 'signed') return 'bg-emerald-25 text-emerald-700';
  if (status === 'pending') return 'bg-amber-25 text-amber-700';
  return 'bg-slate-25 text-slate-600';
};

// The whole point of the audit is being able to show the exact text that was
// accepted, so it is fetched from the frozen version, never re-fetched live.
const showTerms = async acceptance => {
  openAcceptance.value = acceptance;
  openContent.value = '';
  loadingContent.value = true;
  try {
    const res = await fetch(
      `${props.componentData.acceptance_url}/${acceptance.id}.json`,
      { headers: { Accept: 'application/json' }, credentials: 'same-origin' }
    );
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    openContent.value = body.content || '';
  } catch (e) {
    error.value = e.message;
    openAcceptance.value = null;
  } finally {
    loadingContent.value = false;
  }
};

const closeTerms = () => {
  openAcceptance.value = null;
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Termos de uso</h1>
      <p class="text-sm text-slate-500 mt-1">
        Quem aceitou os termos, quando e a partir de onde. O texto guardado aqui
        é a versão exata que a pessoa leu no momento do aceite.
      </p>
    </div>

    <div class="flex items-center gap-4 border-b border-slate-100 mb-4">
      <button
        v-for="tab in TABS"
        :key="tab.id"
        type="button"
        class="pb-2 text-sm border-b-2"
        :class="
          activeTab === tab.id
            ? 'border-woot-500 text-woot-500'
            : 'border-transparent text-slate-500'
        "
        @click="changeTab(tab.id)"
      >
        {{ tab.label }}
      </button>
      <span class="ml-auto text-sm text-slate-400">
        {{ meta.total_count }} registro(s)
      </span>
    </div>

    <div v-if="error" class="p-3 mb-4 rounded bg-red-25 text-sm text-red-700">
      {{ error }}
    </div>

    <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

    <table v-else class="w-full text-sm">
      <thead>
        <tr class="text-left text-slate-500 border-b border-slate-100">
          <th class="py-2">Quem assinou</th>
          <th class="py-2">Conta</th>
          <th class="py-2">Status</th>
          <th class="py-2">Pedido em</th>
          <th class="py-2">Assinado em</th>
          <th class="py-2">Origem</th>
          <th class="py-2 text-right">Termo</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="acceptance in acceptances"
          :key="acceptance.id"
          class="border-b border-slate-50"
        >
          <td class="py-3">
            <div class="text-slate-900">
              {{ acceptance.signer_name || '—' }}
            </div>
            <div class="text-xs text-slate-400 mt-1">
              {{ acceptance.signer_email }}
              <template v-if="acceptance.signer_document">
                · {{ acceptance.signer_document }}
              </template>
            </div>
          </td>

          <td class="py-3 text-slate-700">
            {{ acceptance.account_name || '—' }}
            <div
              v-if="acceptance.sales_quote_id"
              class="text-xs text-slate-400"
            >
              Proposta #{{ acceptance.sales_quote_id }}
            </div>
          </td>

          <td class="py-3">
            <span
              class="px-2 py-0.5 rounded text-xs"
              :class="statusClass(acceptance.status)"
            >
              {{ statusLabel(acceptance.status) }}
            </span>
          </td>

          <td class="py-3 text-slate-700">
            {{ formatDateTime(acceptance.requested_at) }}
          </td>

          <td class="py-3 text-slate-700">
            {{ formatDateTime(acceptance.signed_at) }}
          </td>

          <td class="py-3 text-slate-700">
            {{ acceptance.ip_address || '—' }}
            <div
              v-if="acceptance.user_agent"
              class="text-xs text-slate-400 mt-1 max-w-xs truncate"
              :title="acceptance.user_agent"
            >
              {{ acceptance.user_agent }}
            </div>
          </td>

          <td class="py-3 text-right">
            <button
              type="button"
              class="px-2 py-1 rounded border border-slate-200 text-slate-600 text-xs"
              @click="showTerms(acceptance)"
            >
              Ver termo
            </button>
          </td>
        </tr>

        <tr v-if="!acceptances.length">
          <td colspan="7" class="py-6 text-center text-slate-400">
            Nenhum registro nesta aba.
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

    <div
      v-if="openAcceptance"
      class="fixed inset-0 bg-black/40 flex items-center justify-center p-6 z-50"
      @click.self="closeTerms"
    >
      <div
        class="bg-white rounded-lg w-full max-w-3xl max-h-[85vh] flex flex-col"
      >
        <div class="p-4 border-b border-slate-100">
          <h2 class="text-base font-medium text-slate-900">
            Termo assinado por {{ openAcceptance.signer_name || '—' }}
          </h2>
          <p class="text-xs text-slate-400 mt-1">
            {{ formatDateTime(openAcceptance.signed_at) }} ·
            {{ openAcceptance.ip_address }} · versão
            {{ openAcceptance.content_hash?.slice(0, 12) }}
          </p>
        </div>

        <div class="p-4 overflow-y-auto text-sm text-slate-700 prose-sm">
          <p v-if="loadingContent" class="text-slate-500">Carregando…</p>
          <div v-else v-dompurify-html="openContent" />
        </div>

        <div class="p-4 border-t border-slate-100 text-right">
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm"
            @click="closeTerms"
          >
            Fechar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
