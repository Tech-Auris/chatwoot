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

// Recurring prices of the catalog, offered when starting a subscription.
const prices = ref([]);
const coupons = ref([]);
const subscribingAccount = ref(null);
const creating = ref(false);
const createError = ref(null);
const DEFAULT_DAYS_UNTIL_DUE = 7;
const form = ref({
  price_id: '',
  quantity: 1,
  days_until_due: DEFAULT_DAYS_UNTIL_DUE,
});

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? '';

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
    prices.value = body.prices || [];
    coupons.value = body.coupons || [];
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

const openCreate = account => {
  subscribingAccount.value = account;
  createError.value = null;
  form.value = {
    price_id: prices.value[0]?.id || '',
    quantity: 1,
    days_until_due: DEFAULT_DAYS_UNTIL_DUE,
    coupon_id: '',
  };
};

const closeCreate = () => {
  subscribingAccount.value = null;
};

const submitCreate = async () => {
  creating.value = true;
  createError.value = null;
  try {
    const res = await fetch(props.componentData.create_url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      body: JSON.stringify({
        account_id: subscribingAccount.value.id,
        price_id: form.value.price_id,
        quantity: form.value.quantity,
        days_until_due: form.value.days_until_due,
        coupon_id: form.value.coupon_id,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    closeCreate();
    await fetchData();
  } catch (e) {
    createError.value = e.message;
  } finally {
    creating.value = false;
  }
};

const couponLabel = coupon => {
  const discount = coupon.percent_off
    ? `${coupon.percent_off}%`
    : formatAmount(coupon.amount_off, coupon.currency);
  return `${coupon.name || coupon.id} — ${discount}`;
};

const statusLabel = status => STATUS_LABELS[status] || status;
const statusClass = status =>
  STATUS_CLASSES[status] || 'bg-slate-25 text-slate-600';

const priceLabel = price => {
  const name = price.product_name || 'Produto sem nome';
  const amount = formatAmount(price.unit_amount, price.currency);
  const interval = price.recurring_interval
    ? `/${INTERVAL_LABELS[price.recurring_interval] ?? price.recurring_interval}`
    : '';
  return `${name} — ${amount}${interval}`;
};

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
        Assinaturas no Stripe das contas já conciliadas. Aqui você inicia uma
        assinatura; alterar e cancelar continua sendo feito no painel do Stripe.
        A cobrança é sempre por fatura, para conviver com quem paga por PIX.
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
            <th class="py-2 text-right">Ação</th>
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

            <td class="py-3 text-right whitespace-nowrap">
              <button
                v-if="!account.subscriptions.length"
                type="button"
                class="px-2.5 py-1 rounded bg-woot-500 text-white text-xs disabled:opacity-40"
                :disabled="!prices.length"
                :title="
                  prices.length
                    ? ''
                    : 'Cadastre um produto com preço recorrente em Financeiro → Produtos'
                "
                @click="openCreate(account)"
              >
                Criar assinatura
              </button>
              <span v-else class="text-xs text-slate-400">—</span>
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

    <div
      v-if="subscribingAccount"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    >
      <div class="bg-white rounded-lg shadow-lg w-full max-w-md p-6">
        <h2 class="text-lg font-medium text-slate-900">Criar assinatura</h2>
        <p class="text-sm text-slate-500 mt-1">
          {{ subscribingAccount.name }} — cliente
          {{ subscribingAccount.stripe_customer_id }}
        </p>

        <label class="block mt-4 text-sm text-slate-600">
          Preço
          <select
            v-model="form.price_id"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          >
            <option v-for="price in prices" :key="price.id" :value="price.id">
              {{ priceLabel(price) }}
            </option>
          </select>
        </label>

        <div class="grid grid-cols-2 gap-3 mt-3">
          <label class="block text-sm text-slate-600">
            Quantidade
            <input
              v-model.number="form.quantity"
              type="number"
              min="1"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
          <label class="block text-sm text-slate-600">
            Vencimento (dias)
            <input
              v-model.number="form.days_until_due"
              type="number"
              min="1"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
        </div>

        <label class="block mt-3 text-sm text-slate-600">
          Cupom (opcional)
          <select
            v-model="form.coupon_id"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          >
            <option value="">— sem desconto —</option>
            <option
              v-for="coupon in coupons"
              :key="coupon.id"
              :value="coupon.id"
            >
              {{ couponLabel(coupon) }}
            </option>
          </select>
        </label>

        <p class="text-xs text-slate-400 mt-3">
          A assinatura emite fatura a cada ciclo. Pagamentos recebidos por fora
          (PIX no Inter ou AsaaS) são baixados na fatura correspondente.
        </p>

        <p v-if="createError" class="text-sm text-red-600 mt-3">
          {{ createError }}
        </p>

        <div class="flex justify-end gap-2 mt-5">
          <button
            type="button"
            class="px-3 py-1.5 text-sm text-slate-600"
            :disabled="creating"
            @click="closeCreate"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="creating || !form.price_id"
            @click="submitCreate"
          >
            {{ creating ? 'Criando…' : 'Criar' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
