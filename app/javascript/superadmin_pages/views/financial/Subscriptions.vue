<script setup>
import { ref, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const TABS = [
  { id: 'all', label: 'Todas' },
  { id: 'without_subscription', label: 'Sem assinatura' },
];

const STATUS_LABELS = {
  active: 'Ativa',
  past_due: 'Em atraso',
  unpaid: 'Não paga',
  canceled: 'Cancelada',
  incomplete: 'Incompleta',
  incomplete_expired: 'Incompleta (expirada)',
  trialing: 'Em teste',
  paused: 'Pausada',
};

// Only the states that need someone to act get a colour; the rest stay neutral
// so the table doesn't turn into a christmas tree.
const STATUS_CLASSES = {
  active: 'bg-emerald-25 text-emerald-700',
  trialing: 'bg-emerald-25 text-emerald-700',
  past_due: 'bg-red-25 text-red-700',
  unpaid: 'bg-red-25 text-red-700',
};

const INTERVAL_LABELS = {
  day: 'dia',
  week: 'semana',
  month: 'mês',
  year: 'ano',
};

const activeTab = ref('all');
const accounts = ref([]);
const meta = ref({
  current_page: 1,
  total_pages: 1,
  total_count: 0,
  linked_count: 0,
  without_subscription_count: 0,
});
const page = ref(1);
const search = ref('');
const loading = ref(false);
const error = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({
      scope: activeTab.value,
      page: String(page.value),
    });
    if (search.value.trim()) params.set('search', search.value.trim());

    const res = await fetch(`${props.componentData.data_url}?${params}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    accounts.value = body.accounts || [];
    meta.value = body.meta || meta.value;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  if (props.componentData.configured) fetchData();
});

watch([activeTab, page], fetchData);

const changeTab = tab => {
  if (activeTab.value === tab) return;
  page.value = 1;
  activeTab.value = tab;
};

const submitSearch = () => {
  page.value = 1;
  fetchData();
};

const formatAmount = (amount, currency) => {
  if (amount == null) return '—';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: (currency || 'brl').toUpperCase(),
  }).format(amount / 100);
};

// Stripe timestamps are seconds since the epoch.
const formatDate = timestamp => {
  if (!timestamp) return '—';
  return new Date(timestamp * 1000).toLocaleDateString('pt-BR');
};

const statusLabel = status => STATUS_LABELS[status] || status;
const statusClass = status =>
  STATUS_CLASSES[status] || 'bg-slate-25 text-slate-600';

const itemLabel = item => {
  const name = item.product_name || 'Produto sem nome';
  const price = formatAmount(item.unit_amount, item.currency);
  const interval = item.recurring_interval
    ? `/${INTERVAL_LABELS[item.recurring_interval] ?? item.recurring_interval}`
    : '';
  const quantity = item.quantity > 1 ? ` × ${item.quantity}` : '';
  return `${name} — ${price}${interval}${quantity}`;
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Assinaturas</h1>
      <p class="text-sm text-slate-500 mt-1">
        Assinaturas no Stripe das contas já conciliadas. Esta tela é somente
        leitura — criar e alterar assinatura ainda é feito no painel do Stripe.
      </p>
    </div>

    <div
      v-if="!componentData.configured"
      class="p-4 rounded border border-amber-100 bg-amber-25 text-sm text-amber-700"
    >
      Stripe ainda não configurado. Salve a Stripe Secret Key em
      <a :href="componentData.settings_url" class="underline">
        Settings → Stripe
      </a>
      para liberar esta tela.
    </div>

    <template v-else>
      <div
        v-if="error"
        class="mb-4 p-3 rounded border border-red-100 bg-red-25 text-sm text-red-700"
      >
        {{ error }}
      </div>

      <div class="flex items-center gap-4 border-b border-slate-100 mb-4">
        <button
          v-for="tab in TABS"
          :key="tab.id"
          type="button"
          class="px-1 py-2 text-sm -mb-px border-b-2"
          :class="
            activeTab === tab.id
              ? 'border-woot-500 text-woot-500'
              : 'border-transparent text-slate-600'
          "
          @click="changeTab(tab.id)"
        >
          {{ tab.label }}
          <span class="ml-1 text-xs text-slate-400">
            {{
              tab.id === 'all'
                ? meta.linked_count
                : meta.without_subscription_count
            }}
          </span>
        </button>
      </div>

      <form class="flex items-center gap-3 mb-4" @submit.prevent="submitSearch">
        <input
          v-model="search"
          placeholder="Buscar conta pelo nome"
          class="border border-slate-100 rounded-md p-2 text-sm w-72"
        />
        <button type="submit" class="text-sm text-woot-500">Buscar</button>
        <a
          :href="componentData.links_url"
          class="ml-auto text-xs text-woot-500"
        >
          Contas ainda não conciliadas
        </a>
      </form>

      <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>
      <p v-else-if="!accounts.length" class="text-sm text-slate-500">
        {{
          activeTab === 'without_subscription'
            ? 'Todas as contas conciliadas já têm assinatura.'
            : 'Nenhuma conta conciliada ainda. Comece pela tela de Vínculos.'
        }}
      </p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr
            class="text-left text-xs uppercase text-slate-500 border-b border-slate-100"
          >
            <th class="py-2">Conta</th>
            <th class="py-2">Assinatura</th>
            <th class="py-2">Status</th>
            <th class="py-2 text-right">Valor</th>
            <th class="py-2 text-right">Próxima cobrança</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="account in accounts"
            :key="account.id"
            class="border-b border-slate-50 align-top"
          >
            <td class="py-3">
              <div class="text-slate-900">{{ account.name }}</div>
              <div class="text-xs text-slate-400 mt-1">
                {{ account.stripe_customer_id }}
              </div>
            </td>

            <td class="py-3">
              <div
                v-if="!account.subscriptions.length"
                class="text-xs text-amber-700"
              >
                Sem assinatura no Stripe
              </div>
              <div
                v-for="subscription in account.subscriptions"
                :key="subscription.id"
                class="mb-2 last:mb-0"
              >
                <div
                  v-for="item in subscription.items"
                  :key="item.id"
                  class="text-slate-700"
                >
                  {{ itemLabel(item) }}
                </div>
                <div
                  v-if="subscription.cancel_at_period_end"
                  class="text-xs text-amber-700"
                >
                  Cancela no fim do período
                </div>
              </div>
            </td>

            <td class="py-3">
              <div
                v-for="subscription in account.subscriptions"
                :key="subscription.id"
                class="mb-2 last:mb-0"
              >
                <span
                  class="text-xs px-2 py-1 rounded"
                  :class="statusClass(subscription.status)"
                >
                  {{ statusLabel(subscription.status) }}
                </span>
              </div>
            </td>

            <td class="py-3 text-right">
              <div
                v-for="subscription in account.subscriptions"
                :key="subscription.id"
                class="mb-2 last:mb-0 text-slate-700"
              >
                {{
                  formatAmount(subscription.total_amount, subscription.currency)
                }}
              </div>
            </td>

            <td class="py-3 text-right">
              <div
                v-for="subscription in account.subscriptions"
                :key="subscription.id"
                class="mb-2 last:mb-0 text-slate-700"
              >
                {{ formatDate(subscription.current_period_end) }}
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <div
        v-if="meta.total_pages > 1"
        class="flex items-center gap-3 mt-4 text-sm"
      >
        <button
          type="button"
          class="text-woot-500 disabled:opacity-40"
          :disabled="page <= 1"
          @click="page -= 1"
        >
          Anterior
        </button>
        <span class="text-slate-500">
          Página {{ meta.current_page }} de {{ meta.total_pages }}
        </span>
        <button
          type="button"
          class="text-woot-500 disabled:opacity-40"
          :disabled="page >= meta.total_pages"
          @click="page += 1"
        >
          Próxima
        </button>
      </div>
    </template>
  </div>
</template>
