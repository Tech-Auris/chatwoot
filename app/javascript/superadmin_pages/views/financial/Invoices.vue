<script setup>
import { ref, computed, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

// Stripe's own invoice statuses. `draft` is left out of the tabs on purpose:
// a draft has not been sent to anyone and there is nothing to settle yet.
const TABS = [
  { id: 'open', label: 'Em aberto' },
  { id: 'paid', label: 'Pagas' },
  { id: 'uncollectible', label: 'Incobráveis' },
  { id: '', label: 'Todas' },
];

const STATUS_LABELS = {
  draft: 'Rascunho',
  open: 'Em aberto',
  paid: 'Paga',
  uncollectible: 'Incobrável',
  void: 'Cancelada',
};

const SOURCE_LABELS = {
  inter: 'Banco Inter',
  asaas: 'AsaaS',
};

const activeTab = ref('open');
const invoices = ref([]);
const meta = ref({
  has_more: false,
  last_id: null,
  sources: ['inter', 'asaas'],
});
// Cursor pagination: Stripe pages by "everything after this id", so going back
// means remembering where each page started.
const cursors = ref([null]);
const pageIndex = ref(0);
const loading = ref(false);
const error = ref(null);

const accounts = ref([]);
const prices = ref([]);
const creating = ref(false);
const createError = ref(null);
const showCreate = ref(false);
const DEFAULT_DAYS_UNTIL_DUE = 7;
const emptyItem = () => ({
  product_id: '',
  price_id: '',
  quantity: 1,
  description: '',
  amount: '',
});
const newInvoice = ref({
  account_id: '',
  days_until_due: DEFAULT_DAYS_UNTIL_DUE,
  description: '',
  items: [emptyItem()],
});

const payingInvoice = ref(null);
const paidVia = ref('inter');
const paying = ref(false);
const payError = ref(null);

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? '';

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams();
    if (activeTab.value) params.set('status', activeTab.value);
    const cursor = cursors.value[pageIndex.value];
    if (cursor) params.set('starting_after', cursor);

    const res = await fetch(`${props.componentData.data_url}?${params}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    invoices.value = body.invoices || [];
    accounts.value = body.accounts || accounts.value;
    prices.value = body.prices || prices.value;
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

watch([activeTab, pageIndex], fetchData);

const changeTab = tab => {
  if (activeTab.value === tab) return;
  cursors.value = [null];
  pageIndex.value = 0;
  activeTab.value = tab;
};

const nextPage = () => {
  cursors.value = cursors.value
    .slice(0, pageIndex.value + 1)
    .concat(meta.value.last_id);
  pageIndex.value += 1;
};

const previousPage = () => {
  if (pageIndex.value > 0) pageIndex.value -= 1;
};

const formatAmount = (amount, currency) => {
  if (amount == null) return '—';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: (currency || 'brl').toUpperCase(),
  }).format(amount / 100);
};

const formatDate = timestamp => {
  if (!timestamp) return '—';
  return new Date(timestamp * 1000).toLocaleDateString('pt-BR');
};

const statusLabel = status => STATUS_LABELS[status] || status;
const sourceLabel = source => SOURCE_LABELS[source] || source;

// Past due is not a Stripe status — it is an open invoice whose due date has
// gone by, which is exactly the list somebody has to chase.
const isOverdue = invoice =>
  invoice.status === 'open' &&
  invoice.due_date &&
  invoice.due_date * 1000 < Date.now();

const statusClass = invoice => {
  if (isOverdue(invoice)) return 'bg-red-25 text-red-700';
  if (invoice.status === 'paid') return 'bg-emerald-25 text-emerald-700';
  if (invoice.status === 'open') return 'bg-amber-25 text-amber-700';
  return 'bg-slate-25 text-slate-600';
};

const overdueCount = computed(() => invoices.value.filter(isOverdue).length);

const openCreate = () => {
  showCreate.value = true;
  createError.value = null;
  newInvoice.value = {
    account_id: accounts.value[0]?.id || '',
    days_until_due: DEFAULT_DAYS_UNTIL_DUE,
    description: '',
    items: [emptyItem()],
  };
};

const closeCreate = () => {
  showCreate.value = false;
};

const addItem = () => {
  newInvoice.value.items.push(emptyItem());
};

const removeItem = index => {
  newInvoice.value.items.splice(index, 1);
  if (!newInvoice.value.items.length) newInvoice.value.items.push(emptyItem());
};

// A line is worth sending when it points at a catalog price or carries a typed
// amount; the empty rows of the form are just noise.
const filledItems = computed(() =>
  newInvoice.value.items
    .filter(item => item.price_id || item.amount)
    .map(({ price_id, quantity, description, amount }) => ({
      price_id,
      quantity,
      description,
      amount,
    }))
);

// A product carries a one-off price and a monthly one, often of the same
// amount. The form asks for the product first and then for which of its prices
// to charge, instead of a flat list where the two read identically.
const products = computed(() => {
  const byId = new Map();
  prices.value.forEach(price => {
    if (!byId.has(price.product_id)) {
      byId.set(price.product_id, {
        id: price.product_id,
        name: price.product_name || 'Produto sem nome',
      });
    }
  });
  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
});

const pricesOfProduct = productId =>
  prices.value.filter(price => price.product_id === productId);

const priceLabel = price =>
  `${formatAmount(price.unit_amount, price.currency)} — ${
    price.recurring_interval ? 'Mensal' : 'Avulso'
  }`;

const onItemProductChange = item => {
  const options = pricesOfProduct(item.product_id);
  item.price_id = options.length === 1 ? options[0].id : '';
};

const submitCreate = async () => {
  creating.value = true;
  createError.value = null;
  try {
    const res = await fetch(props.componentData.invoices_url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      body: JSON.stringify({
        account_id: newInvoice.value.account_id,
        days_until_due: newInvoice.value.days_until_due,
        description: newInvoice.value.description,
        items: filledItems.value,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    closeCreate();
    activeTab.value = 'open';
    cursors.value = [null];
    pageIndex.value = 0;
    await fetchData();
  } catch (e) {
    createError.value = e.message;
  } finally {
    creating.value = false;
  }
};

const openPay = invoice => {
  payingInvoice.value = invoice;
  paidVia.value = meta.value.sources?.[0] || 'inter';
  payError.value = null;
};

const closePay = () => {
  payingInvoice.value = null;
};

const submitPay = async () => {
  paying.value = true;
  payError.value = null;
  try {
    const res = await fetch(
      `${props.componentData.invoices_url}/${payingInvoice.value.id}/pay`,
      {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({ paid_via: paidVia.value }),
      }
    );
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);

    closePay();
    await fetchData();
  } catch (e) {
    payError.value = e.message;
  } finally {
    paying.value = false;
  }
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6 flex items-start justify-between gap-4">
      <div>
        <h1 class="text-xl font-medium text-slate-900">Faturas</h1>
        <p class="text-sm text-slate-500 mt-1">
          Faturas emitidas pelo Stripe. Quem paga por PIX no Inter ou pelo AsaaS
          é baixado aqui, registrando por onde o dinheiro entrou.
        </p>
      </div>
      <button
        v-if="componentData.configured"
        type="button"
        class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm whitespace-nowrap disabled:opacity-40"
        :disabled="!accounts.length"
        :title="
          accounts.length
            ? ''
            : 'Vincule uma conta a um cliente do Stripe em Financeiro → Vínculos'
        "
        @click="openCreate"
      >
        Nova fatura
      </button>
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
        <span v-if="overdueCount" class="ml-auto text-xs text-red-700">
          {{ overdueCount }} vencida(s) nesta página
        </span>
      </div>

      <div v-if="error" class="p-3 mb-4 rounded bg-red-25 text-sm text-red-700">
        {{ error }}
      </div>

      <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-slate-500 border-b border-slate-100">
            <th class="py-2">Conta</th>
            <th class="py-2">Fatura</th>
            <th class="py-2">Produto</th>
            <th class="py-2">Status</th>
            <th class="py-2 text-right">Valor</th>
            <th class="py-2 text-right">Vencimento</th>
            <th class="py-2 text-right">Ação</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="invoice in invoices"
            :key="invoice.id"
            class="border-b border-slate-50"
          >
            <td class="py-3">
              <div class="text-slate-900">
                {{ invoice.account_name || invoice.customer_name || '—' }}
              </div>
              <div
                v-if="!invoice.account_name"
                class="text-xs text-amber-700 mt-1"
              >
                Cliente sem conta vinculada
              </div>
            </td>

            <td class="py-3">
              <a
                v-if="invoice.hosted_invoice_url"
                :href="invoice.hosted_invoice_url"
                target="_blank"
                rel="noopener noreferrer"
                class="text-woot-500 underline"
              >
                {{ invoice.number || invoice.id }}
              </a>
              <span v-else class="text-slate-700">
                {{ invoice.number || invoice.id }}
              </span>
              <div v-if="invoice.paid_via" class="text-xs text-slate-400 mt-1">
                Baixa manual — {{ sourceLabel(invoice.paid_via) }}
              </div>
            </td>

            <td class="py-3 text-slate-700">
              <div
                v-for="product in invoice.products"
                :key="product"
                class="mb-1 last:mb-0"
              >
                {{ product }}
              </div>
              <span v-if="!invoice.products?.length" class="text-slate-400">
                —
              </span>
            </td>

            <td class="py-3">
              <span
                class="text-xs px-2 py-1 rounded"
                :class="statusClass(invoice)"
              >
                {{
                  isOverdue(invoice) ? 'Vencida' : statusLabel(invoice.status)
                }}
              </span>
            </td>

            <td class="py-3 text-right text-slate-700">
              {{ formatAmount(invoice.amount_due, invoice.currency) }}
            </td>

            <td class="py-3 text-right text-slate-700">
              {{ formatDate(invoice.due_date) }}
            </td>

            <td class="py-3 text-right whitespace-nowrap">
              <button
                v-if="invoice.status === 'open'"
                type="button"
                class="px-2.5 py-1 rounded bg-woot-500 text-white text-xs"
                @click="openPay(invoice)"
              >
                Pago por fora
              </button>
              <span v-else class="text-xs text-slate-400">—</span>
            </td>
          </tr>
          <tr v-if="!invoices.length">
            <td colspan="7" class="py-6 text-center text-slate-500">
              Nenhuma fatura neste filtro.
            </td>
          </tr>
        </tbody>
      </table>

      <div
        v-if="pageIndex > 0 || meta.has_more"
        class="flex items-center gap-3 mt-4 text-sm"
      >
        <button
          type="button"
          class="text-woot-500 disabled:opacity-40"
          :disabled="pageIndex === 0"
          @click="previousPage"
        >
          Anterior
        </button>
        <span class="text-slate-500">Página {{ pageIndex + 1 }}</span>
        <button
          type="button"
          class="text-woot-500 disabled:opacity-40"
          :disabled="!meta.has_more"
          @click="nextPage"
        >
          Próxima
        </button>
      </div>
    </template>

    <div
      v-if="showCreate"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    >
      <div
        class="bg-white rounded-lg shadow-lg w-full max-w-2xl p-6 max-h-[90vh] overflow-y-auto"
      >
        <h2 class="text-lg font-medium text-slate-900">Nova fatura</h2>
        <p class="text-sm text-slate-500 mt-1">
          Emite uma fatura avulsa — a cobrança mensal de tokens, um serviço
          extra, qualquer coisa fora da assinatura.
        </p>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mt-4">
          <label class="block text-sm text-slate-600 md:col-span-2">
            Conta
            <select
              v-model="newInvoice.account_id"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            >
              <option
                v-for="account in accounts"
                :key="account.id"
                :value="account.id"
              >
                {{ account.name }}
              </option>
            </select>
          </label>
          <label class="block text-sm text-slate-600">
            Vencimento (dias)
            <input
              v-model.number="newInvoice.days_until_due"
              type="number"
              min="1"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
        </div>

        <div class="mt-4">
          <div class="flex items-center justify-between">
            <span class="text-sm text-slate-600">Itens</span>
            <button
              type="button"
              class="text-xs text-woot-500"
              @click="addItem"
            >
              + Adicionar item
            </button>
          </div>

          <div
            v-for="(item, index) in newInvoice.items"
            :key="index"
            class="border border-slate-100 rounded p-3 mt-2"
          >
            <div class="grid grid-cols-2 gap-2">
              <label class="block text-xs text-slate-500">
                Produto do catálogo
                <select
                  v-model="item.product_id"
                  class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
                  @change="onItemProductChange(item)"
                >
                  <option value="">— valor avulso —</option>
                  <option
                    v-for="product in products"
                    :key="product.id"
                    :value="product.id"
                  >
                    {{ product.name }}
                  </option>
                </select>
              </label>
              <label class="block text-xs text-slate-500">
                Preço
                <select
                  v-model="item.price_id"
                  :disabled="!item.product_id"
                  class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm disabled:bg-slate-25"
                >
                  <option value="">— escolher —</option>
                  <option
                    v-for="price in pricesOfProduct(item.product_id)"
                    :key="price.id"
                    :value="price.id"
                  >
                    {{ priceLabel(price) }}
                  </option>
                </select>
              </label>
            </div>

            <div class="grid grid-cols-3 gap-2 mt-2">
              <label class="block text-xs text-slate-500">
                Quantidade
                <input
                  v-model.number="item.quantity"
                  type="number"
                  min="1"
                  class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
                />
              </label>
              <label class="block text-xs text-slate-500 col-span-2">
                Descrição
                <input
                  v-model="item.description"
                  type="text"
                  :disabled="!!item.price_id"
                  placeholder="Ex: Pacote de tokens — agosto"
                  class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm disabled:bg-slate-25"
                />
              </label>
            </div>

            <div class="grid grid-cols-3 gap-2 mt-2 items-end">
              <label class="block text-xs text-slate-500">
                Valor unitário (R$)
                <input
                  v-model="item.amount"
                  type="number"
                  min="0"
                  step="0.01"
                  :disabled="!!item.price_id"
                  class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm disabled:bg-slate-25"
                />
              </label>
              <div class="col-span-2 text-right">
                <button
                  type="button"
                  class="text-xs text-slate-500"
                  @click="removeItem(index)"
                >
                  Remover item
                </button>
              </div>
            </div>
          </div>
        </div>

        <label class="block mt-4 text-sm text-slate-600">
          Observação na fatura (opcional)
          <input
            v-model="newInvoice.description"
            type="text"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          />
        </label>

        <p class="text-xs text-slate-400 mt-3">
          A fatura é emitida já em aberto, pronta para pagamento ou para baixa
          manual. O envio de e-mail ao cliente segue a configuração da sua conta
          no Stripe — nada é disparado por aqui.
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
            :disabled="
              creating || !newInvoice.account_id || !filledItems.length
            "
            @click="submitCreate"
          >
            {{ creating ? 'Emitindo…' : 'Emitir fatura' }}
          </button>
        </div>
      </div>
    </div>

    <div
      v-if="payingInvoice"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    >
      <div class="bg-white rounded-lg shadow-lg w-full max-w-sm p-6">
        <h2 class="text-lg font-medium text-slate-900">Dar baixa na fatura</h2>
        <p class="text-sm text-slate-500 mt-1">
          {{ payingInvoice.account_name || payingInvoice.customer_name }} —
          {{ formatAmount(payingInvoice.amount_due, payingInvoice.currency) }}
        </p>

        <label class="block mt-4 text-sm text-slate-600">
          Onde o dinheiro entrou
          <select
            v-model="paidVia"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          >
            <option
              v-for="source in meta.sources"
              :key="source"
              :value="source"
            >
              {{ sourceLabel(source) }}
            </option>
          </select>
        </label>

        <p class="text-xs text-slate-400 mt-3">
          A fatura será marcada como paga fora do Stripe. A origem fica gravada
          na própria fatura, para conferência depois.
        </p>

        <p v-if="payError" class="text-sm text-red-600 mt-3">{{ payError }}</p>

        <div class="flex justify-end gap-2 mt-5">
          <button
            type="button"
            class="px-3 py-1.5 text-sm text-slate-600"
            :disabled="paying"
            @click="closePay"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="paying"
            @click="submitPay"
          >
            {{ paying ? 'Registrando…' : 'Confirmar baixa' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
