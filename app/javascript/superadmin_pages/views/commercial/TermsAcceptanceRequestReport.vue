<script setup>
import { ref, onMounted, computed } from 'vue';

const props = defineProps({
  componentData: { type: Object, default: () => ({}) },
});

const campaign = ref(null);
const accounts = ref([]);
const loading = ref(true);
const error = ref(null);

const KIND_LABELS = { signature: 'Assinatura', update: 'Atualização' };
const STATUS_LABELS = {
  open: 'Aberta',
  expired: 'Vencida',
  closed: 'Encerrada',
};
const SIGN_STATUS_LABELS = {
  pending: 'Aguardando',
  signed: 'Assinado',
  cancelled: 'Cancelado',
};

const fetchReport = async () => {
  loading.value = true;
  error.value = null;
  try {
    const res = await fetch(props.componentData.report_url, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    campaign.value = body.campaign;
    accounts.value = body.accounts || [];
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

const formatDate = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';
const formatDateTime = value =>
  value ? new Date(value).toLocaleString('pt-BR') : '—';

const accountStatus = account => {
  const required = account.signers.filter(s => s.required);
  const signed = required.filter(s => s.status === 'signed').length;
  if (signed === required.length) return 'complete';
  if (signed === 0) return 'none';
  return 'partial';
};

const totalSigned = computed(() =>
  accounts.value.reduce(
    (sum, a) => sum + a.signers.filter(s => s.status === 'signed').length,
    0
  )
);
const totalRequired = computed(() =>
  accounts.value.reduce(
    (sum, a) => sum + a.signers.filter(s => s.required).length,
    0
  )
);

const backToList = () => {
  window.location.href = props.componentData.index_url;
};

onMounted(fetchReport);
</script>

<template>
  <div class="p-6">
    <div class="mb-4">
      <button type="button" class="text-sm text-woot-500" @click="backToList">
        ← Voltar para campanhas
      </button>
    </div>

    <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
      {{ error }}
    </div>

    <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

    <div v-else-if="campaign">
      <div class="mb-6">
        <h1 class="text-xl font-medium text-slate-900">
          Campanha #{{ campaign.id }}
        </h1>
        <div class="text-sm text-slate-500 mt-1 flex flex-wrap gap-x-4">
          <span
            >Tipo:
            <b>{{ KIND_LABELS[campaign.kind] || campaign.kind }}</b></span
          >
          <span
            >Status:
            <b>{{ STATUS_LABELS[campaign.status] || campaign.status }}</b></span
          >
          <span
            >Data do documento:
            <b>{{ formatDate(campaign.document_date) }}</b></span
          >
          <span
            >Vence em: <b>{{ formatDateTime(campaign.deadline_at) }}</b></span
          >
          <span
            >Criada por: <b>{{ campaign.created_by || '—' }}</b></span
          >
          <span
            >Assinaturas: <b>{{ totalSigned }} / {{ totalRequired }}</b></span
          >
        </div>
      </div>

      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-slate-500 border-b border-slate-100">
            <th class="py-2">Conta</th>
            <th class="py-2">Gerente</th>
            <th class="py-2">Obrigatório</th>
            <th class="py-2">Status</th>
            <th class="py-2">Assinou em</th>
            <th class="py-2">Origem</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="account in accounts" :key="account.account_id">
            <tr
              v-for="(signer, idx) in account.signers"
              :key="signer.acceptance_id"
              class="border-b border-slate-50"
            >
              <td class="py-3 text-slate-700 align-top">
                <template v-if="idx === 0">
                  <div class="font-medium text-slate-800">
                    {{ account.account_name }}
                  </div>
                  <div
                    class="text-xs mt-1"
                    :class="{
                      'text-green-600': accountStatus(account) === 'complete',
                      'text-yellow-600': accountStatus(account) === 'partial',
                      'text-red-600': accountStatus(account) === 'none',
                    }"
                  >
                    {{
                      accountStatus(account) === 'complete'
                        ? 'Todas as assinaturas obtidas'
                        : accountStatus(account) === 'partial'
                          ? 'Assinaturas parciais'
                          : 'Sem assinaturas'
                    }}
                  </div>
                </template>
              </td>
              <td class="py-3 text-slate-700">
                {{ signer.user_name || signer.user_email }}
                <div class="text-xs text-slate-400">
                  {{ signer.user_email }}
                </div>
              </td>
              <td class="py-3 text-slate-700">
                <span
                  v-if="signer.required"
                  class="px-2 py-0.5 rounded text-xs bg-slate-100 text-slate-700"
                >
                  Sim
                </span>
                <span v-else class="text-xs text-slate-400">Não</span>
              </td>
              <td class="py-3 text-slate-700">
                <span
                  class="px-2 py-0.5 rounded text-xs"
                  :class="{
                    'bg-green-50 text-green-700': signer.status === 'signed',
                    'bg-yellow-50 text-yellow-700': signer.status === 'pending',
                    'bg-slate-100 text-slate-500':
                      signer.status === 'cancelled',
                  }"
                >
                  {{ SIGN_STATUS_LABELS[signer.status] || signer.status }}
                </span>
              </td>
              <td class="py-3 text-slate-700">
                {{ formatDateTime(signer.signed_at) }}
              </td>
              <td class="py-3 text-slate-500 text-xs">
                {{ signer.ip_address || '—' }}
              </td>
            </tr>
          </template>
          <tr v-if="!accounts.length">
            <td colspan="6" class="py-6 text-center text-slate-400">
              Nenhum assinante nesta campanha.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
