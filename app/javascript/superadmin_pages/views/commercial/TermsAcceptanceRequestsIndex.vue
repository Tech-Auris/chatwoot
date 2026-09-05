<script setup>
import { ref, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: { type: Object, default: () => ({}) },
});

const KIND_LABELS = { signature: 'Assinatura', update: 'Atualização' };
const STATUS_LABELS = {
  open: 'Aberta',
  expired: 'Vencida',
  closed: 'Encerrada',
};

const requests = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const page = ref(1);
const loading = ref(false);
const error = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const res = await fetch(
      `${props.componentData.data_url}?page=${page.value}`,
      {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      }
    );
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    requests.value = body.requests || [];
    meta.value = body.meta || meta.value;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);
watch(page, fetchData);

const formatDate = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';
const formatDateTime = value =>
  value ? new Date(value).toLocaleString('pt-BR') : '—';

const openCampaign = campaign => {
  window.location.href = `${props.componentData.request_url}/${campaign.id}`;
};

const startNew = () => {
  window.location.href = props.componentData.new_url;
};
</script>

<template>
  <div class="p-6">
    <div class="flex items-start justify-between mb-6">
      <div>
        <h1 class="text-xl font-medium text-slate-900">
          Campanhas de termos de uso
        </h1>
        <p class="text-sm text-slate-500 mt-1">
          Cada campanha pede o aceite da versão vigente aos gerentes das contas.
          A auditoria individual dos aceites fica na tela "Terms of use".
        </p>
      </div>
      <button
        type="button"
        class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm"
        @click="startNew"
      >
        Nova campanha
      </button>
    </div>

    <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
      {{ error }}
    </div>

    <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

    <table v-else class="w-full text-sm">
      <thead>
        <tr class="text-left text-slate-500 border-b border-slate-100">
          <th class="py-2">#</th>
          <th class="py-2">Tipo</th>
          <th class="py-2">Data do documento</th>
          <th class="py-2">Vence em</th>
          <th class="py-2">Status</th>
          <th class="py-2">Assinados</th>
          <th class="py-2">Criada por</th>
          <th class="py-2">Criada em</th>
          <th class="py-2 text-right" />
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="request in requests"
          :key="request.id"
          class="border-b border-slate-50 cursor-pointer hover:bg-slate-25"
          @click="openCampaign(request)"
        >
          <td class="py-3 text-slate-700">{{ request.id }}</td>
          <td class="py-3 text-slate-700">
            {{ KIND_LABELS[request.kind] || request.kind }}
          </td>
          <td class="py-3 text-slate-700">
            {{ formatDate(request.document_date) }}
          </td>
          <td class="py-3 text-slate-700">
            {{ formatDateTime(request.deadline_at) }}
          </td>
          <td class="py-3 text-slate-700">
            {{ STATUS_LABELS[request.status] || request.status }}
          </td>
          <td class="py-3 text-slate-700">
            {{ request.signed_count }} / {{ request.total_count }}
          </td>
          <td class="py-3 text-slate-700">{{ request.created_by || '—' }}</td>
          <td class="py-3 text-slate-700">
            {{ formatDateTime(request.created_at) }}
          </td>
          <td class="py-3 text-right text-woot-500 text-xs">Ver →</td>
        </tr>
        <tr v-if="!requests.length">
          <td colspan="9" class="py-6 text-center text-slate-400">
            Nenhuma campanha criada ainda.
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
