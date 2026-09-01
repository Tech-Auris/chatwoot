<script setup>
import { ref, computed, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

// What the proposal is worth to us, as opposed to where ClickUp says the deal
// is. Only a converted proposal is a customer.
const STATUS_LABELS = {
  draft: 'Rascunho',
  reserved: 'Reservada',
  details_confirmed: 'Dados confirmados',
  signed: 'Termos assinados',
  paid: 'Paga',
  converted: 'Conta criada',
  expired: 'Expirada',
  cancelled: 'Cancelada',
};

const reservations = ref([]);
const statuses = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
// The screen opens showing every proposal; the status narrows it down.
const statusFilter = ref('');
const page = ref(1);
const loading = ref(false);
const error = ref(null);
// Which row was copied and what was taken from it, so the feedback lands on the
// button that was actually pressed.
const copied = ref({ id: null, field: null });
const busyId = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({ page: page.value });
    if (statusFilter.value) params.set('clickup_status', statusFilter.value);

    const res = await fetch(`${props.componentData.data_url}?${params}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    reservations.value = body.reservations || [];
    statuses.value = body.statuses || [];
    meta.value = body.meta || meta.value;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

watch(page, fetchData);
watch(statusFilter, () => {
  page.value = 1;
  fetchData();
});

const formatAmount = amount =>
  amount == null
    ? '—'
    : new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: 'BRL',
      }).format(amount / 100);

const formatDate = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';

const statusLabel = status => STATUS_LABELS[status] || status;

const isExpiring = reservation =>
  reservation.reservation_active &&
  new Date(reservation.reserved_until) - Date.now() < 3 * 24 * 60 * 60 * 1000;

const deadlineClass = reservation => {
  if (reservation.won) return 'text-slate-500';
  if (!reservation.reservation_active) return 'text-red-700';
  return isExpiring(reservation) ? 'text-yellow-700' : 'text-slate-700';
};

const expiringCount = computed(
  () => reservations.value.filter(r => !r.won && isExpiring(r)).length
);

// The link and the code are copied apart on purpose: sending both in the same
// message would make the code pointless, since it exists so that a forwarded
// link alone opens nothing.
// Somebody who paid the year by PIX may have no card to leave on file. The
// team says so here, and the customer stops being asked for one.
const waiveTokenCard = async reservation => {
  if (
    !window.confirm(
      'Dispensar o cartão dos tokens? O consumo passa a ser cobrado por fatura.'
    )
  )
    return;

  busyId.value = reservation.id;
  error.value = null;
  try {
    const res = await fetch(
      `${props.componentData.reservations_url}/${reservation.id}/waive_token_card`,
      {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          Accept: 'application/json',
          'X-CSRF-Token':
            document.querySelector('meta[name="csrf-token"]')?.content ?? '',
        },
      }
    );
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    await fetchData();
  } catch (e) {
    error.value = e.message;
  } finally {
    busyId.value = null;
  }
};

const copy = async (reservation, field, value) => {
  await navigator.clipboard.writeText(value);
  copied.value = { id: reservation.id, field };
  window.setTimeout(() => {
    if (copied.value.id === reservation.id && copied.value.field === field)
      copied.value = { id: null, field: null };
  }, 2000);
};

const wasCopied = (reservation, field) =>
  copied.value.id === reservation.id && copied.value.field === field;
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Reservas</h1>
      <p class="text-sm text-slate-500 mt-1">
        Propostas enviadas e o prazo de cada reserva. O status e o vencimento
        vêm do ClickUp e são atualizados a cada abertura desta tela.
      </p>
    </div>

    <div
      v-if="!componentData.clickup_configured"
      class="p-4 rounded border border-yellow-100 bg-yellow-50 text-sm text-yellow-700"
    >
      ClickUp ainda não configurado. Informe o token e a lista do pipeline em
      <a :href="componentData.settings_url" class="underline">
        Settings → ClickUp
      </a>
      para o status e o vencimento ficarem em dia.
    </div>

    <div class="flex items-center gap-3 mb-4">
      <label class="text-sm text-slate-500">Status no ClickUp</label>
      <select
        v-model="statusFilter"
        class="text-sm border border-slate-200 rounded px-2 py-1"
      >
        <option value="">Todos</option>
        <option v-for="status in statuses" :key="status" :value="status">
          {{ status }}
        </option>
      </select>
      <span class="text-sm text-slate-400">
        {{ meta.total_count }} proposta(s)
      </span>
      <span v-if="expiringCount" class="ml-auto text-xs text-yellow-700">
        {{ expiringCount }} reserva(s) vencendo em até 3 dias
      </span>
    </div>

    <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
      {{ error }}
    </div>

    <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

    <table v-else class="w-full text-sm">
      <thead>
        <tr class="text-left text-slate-500 border-b border-slate-100">
          <th class="py-2">Cliente</th>
          <th class="py-2">Vendedor</th>
          <th class="py-2">Status no ClickUp</th>
          <th class="py-2">Situação</th>
          <th class="py-2 text-right">Valor</th>
          <th class="py-2 text-right">Reserva até</th>
          <th class="py-2">Tokens</th>
          <th class="py-2 text-right">Link e código</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="reservation in reservations"
          :key="reservation.id"
          class="border-b border-slate-50"
        >
          <td class="py-3">
            <div class="text-slate-900">{{ reservation.prospect_name }}</div>
            <div
              v-if="reservation.contact_name !== reservation.prospect_name"
              class="text-xs text-slate-400 mt-1"
            >
              {{ reservation.contact_name }}
            </div>
          </td>

          <td class="py-3 text-slate-700">
            {{ reservation.seller_name || '—' }}
          </td>

          <td class="py-3">
            <a
              :href="reservation.clickup_url"
              target="_blank"
              rel="noopener noreferrer"
              class="text-woot-500 underline"
            >
              {{ reservation.clickup_status || 'Sem status' }}
            </a>
          </td>

          <td class="py-3">
            <span
              class="px-2 py-0.5 rounded text-xs"
              :class="
                reservation.won
                  ? 'bg-green-50 text-green-700'
                  : 'bg-slate-25 text-slate-600'
              "
            >
              {{ reservation.won ? 'Ganho' : statusLabel(reservation.status) }}
            </span>
          </td>

          <td class="py-3 text-right text-slate-700">
            {{ formatAmount(reservation.total_amount) }}
          </td>

          <td class="py-3 text-right" :class="deadlineClass(reservation)">
            {{ formatDate(reservation.reserved_until) }}
            <div
              v-if="!reservation.won && !reservation.reservation_active"
              class="text-xs mt-1"
            >
              Reserva vencida
            </div>
          </td>

          <td class="py-3">
            <span
              v-if="reservation.token_card_saved"
              class="text-xs text-slate-500"
            >
              Cartão cadastrado
            </span>
            <span
              v-else-if="reservation.token_card_waived"
              class="text-xs text-slate-500"
            >
              Cobrança por fatura
            </span>
            <button
              v-else
              type="button"
              class="px-2 py-1 rounded border border-slate-200 text-slate-600 text-xs whitespace-nowrap disabled:opacity-40"
              :disabled="busyId === reservation.id"
              title="Para quem pagou por PIX e não tem cartão. O consumo passa a ser cobrado por fatura."
              @click="waiveTokenCard(reservation)"
            >
              Dispensar cartão
            </button>
          </td>

          <td class="py-3 text-right">
            <div class="flex gap-2 justify-end">
              <button
                type="button"
                class="px-2 py-1 rounded border border-slate-200 text-slate-600 text-xs whitespace-nowrap"
                @click="copy(reservation, 'link', reservation.public_url)"
              >
                {{
                  wasCopied(reservation, 'link') ? 'Copiado!' : 'Copiar link'
                }}
              </button>
              <button
                type="button"
                class="px-2 py-1 rounded border border-slate-200 text-slate-600 text-xs whitespace-nowrap"
                :title="`Código de acesso: ${reservation.access_code}`"
                @click="copy(reservation, 'code', reservation.access_code)"
              >
                {{
                  wasCopied(reservation, 'code')
                    ? 'Copiado!'
                    : reservation.access_code
                }}
              </button>
            </div>
          </td>
        </tr>

        <tr v-if="!reservations.length">
          <td colspan="8" class="py-6 text-center text-slate-400">
            {{
              statusFilter
                ? 'Nenhuma proposta com este status.'
                : 'Nenhuma proposta enviada ainda.'
            }}
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
