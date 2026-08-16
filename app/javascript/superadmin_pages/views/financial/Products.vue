<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const products = ref([]);
const loading = ref(false);
const error = ref(null);
const saving = ref(false);
const showArchived = ref(false);
const search = ref('');

// Which product is being edited / receiving a new price. Only one row is open
// at a time so the table stays readable.
const editingId = ref(null);
const pricingId = ref(null);
const showNewProduct = ref(false);

const editForm = ref({ name: '', description: '' });
const priceForm = ref({
  unit_amount: '',
  currency: 'brl',
  recurring_interval: 'month',
});
const newProduct = ref({
  name: '',
  description: '',
  unit_amount: '',
  currency: 'brl',
  recurring_interval: 'month',
});

const INTERVAL_LABELS = {
  '': 'Avulso (sem recorrência)',
  day: 'Diário',
  week: 'Semanal',
  month: 'Mensal',
  year: 'Anual',
};

const csrfToken = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? '';

const request = async (url, { method = 'GET', body } = {}) => {
  const res = await fetch(url, {
    method,
    credentials: 'same-origin',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken(),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload.error || `HTTP ${res.status}`);
  return payload;
};

const fetchProducts = async () => {
  loading.value = true;
  error.value = null;
  try {
    const body = await request(props.componentData.data_url);
    products.value = body.products || [];
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  if (props.componentData.configured) fetchProducts();
});

const visibleProducts = computed(() => {
  const term = search.value.trim().toLowerCase();
  return products.value.filter(product => {
    if (!showArchived.value && !product.active) return false;
    if (!term) return true;
    return (
      product.name?.toLowerCase().includes(term) ||
      product.description?.toLowerCase().includes(term)
    );
  });
});

const formatAmount = price => {
  if (price?.unit_amount == null) return '—';
  const value = price.unit_amount / 100;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: (price.currency || 'brl').toUpperCase(),
  }).format(value);
};

const formatPrice = price => {
  const amount = formatAmount(price);
  const interval = price.recurring_interval
    ? ` / ${INTERVAL_LABELS[price.recurring_interval] ?? price.recurring_interval}`
    : '';
  return `${amount}${interval}`;
};

// Amount is typed in reais and Stripe stores cents.
const toCents = value =>
  Math.round(Number(String(value).replace(',', '.')) * 100);

const run = async (fn, { onDone } = {}) => {
  saving.value = true;
  error.value = null;
  try {
    await fn();
    if (onDone) onDone();
    await fetchProducts();
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

const startEdit = product => {
  pricingId.value = null;
  editingId.value = product.id;
  editForm.value = {
    name: product.name,
    description: product.description || '',
  };
};

const startPricing = product => {
  editingId.value = null;
  pricingId.value = product.id;
  priceForm.value = {
    unit_amount: '',
    currency: 'brl',
    recurring_interval: 'month',
  };
};

const productUrl = id => `${props.componentData.products_url}/${id}`;

const submitEdit = product =>
  run(
    () =>
      request(productUrl(product.id), {
        method: 'PATCH',
        body: { product: editForm.value },
      }),
    {
      onDone: () => {
        editingId.value = null;
      },
    }
  );

const submitPrice = product =>
  run(
    () =>
      request(`${productUrl(product.id)}/prices`, {
        method: 'POST',
        body: {
          price: {
            unit_amount: toCents(priceForm.value.unit_amount),
            currency: priceForm.value.currency,
            recurring_interval: priceForm.value.recurring_interval,
          },
        },
      }),
    {
      onDone: () => {
        pricingId.value = null;
      },
    }
  );

const archiveProduct = product => {
  const message = `Arquivar "${product.name}"? Ele deixa de aparecer para novas assinaturas, mas as assinaturas e faturas existentes continuam válidas.`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;
  run(() => request(productUrl(product.id), { method: 'DELETE' }));
};

const reactivateProduct = product =>
  run(() =>
    request(productUrl(product.id), {
      method: 'PATCH',
      body: { product: { active: true } },
    })
  );

const submitNewProduct = () =>
  run(
    () =>
      request(props.componentData.products_url, {
        method: 'POST',
        body: {
          product: {
            name: newProduct.value.name,
            description: newProduct.value.description,
          },
          price: newProduct.value.unit_amount
            ? {
                unit_amount: toCents(newProduct.value.unit_amount),
                currency: newProduct.value.currency,
                recurring_interval: newProduct.value.recurring_interval,
              }
            : {},
        },
      }),
    {
      onDone: () => {
        showNewProduct.value = false;
        newProduct.value = {
          name: '',
          description: '',
          unit_amount: '',
          currency: 'brl',
          recurring_interval: 'month',
        };
      },
    }
  );
</script>

<template>
  <div class="p-6">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-xl font-medium text-slate-900">Produtos</h1>
        <p class="text-sm text-slate-500 mt-1">
          Catálogo lido direto do Stripe. Alterações feitas aqui vão para o
          Stripe na hora.
        </p>
      </div>
      <button
        v-if="componentData.configured"
        type="button"
        class="px-3 py-2 text-sm rounded-md bg-woot-500 text-white hover:brightness-110"
        @click="showNewProduct = !showNewProduct"
      >
        Novo produto
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
      <div
        v-if="error"
        class="mb-4 p-3 rounded border border-red-100 bg-red-25 text-sm text-red-700"
      >
        {{ error }}
      </div>

      <form
        v-if="showNewProduct"
        class="mb-6 p-4 rounded border border-slate-100 bg-slate-25"
        @submit.prevent="submitNewProduct"
      >
        <h2 class="text-sm font-medium text-slate-800 mb-3">Novo produto</h2>
        <div class="grid grid-cols-2 gap-3">
          <label class="text-xs text-slate-600">
            Nome
            <input
              v-model="newProduct.name"
              required
              class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
            />
          </label>
          <label class="text-xs text-slate-600">
            Descrição
            <input
              v-model="newProduct.description"
              class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
            />
          </label>
          <label class="text-xs text-slate-600">
            Valor (opcional, em reais)
            <input
              v-model="newProduct.unit_amount"
              inputmode="decimal"
              placeholder="199,90"
              class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
            />
          </label>
          <label class="text-xs text-slate-600">
            Recorrência
            <select
              v-model="newProduct.recurring_interval"
              class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
            >
              <option
                v-for="(label, value) in INTERVAL_LABELS"
                :key="value"
                :value="value"
              >
                {{ label }}
              </option>
            </select>
          </label>
        </div>
        <div class="flex gap-2 mt-4">
          <button
            type="submit"
            :disabled="saving"
            class="px-3 py-2 text-sm rounded-md bg-woot-500 text-white disabled:opacity-50"
          >
            Criar
          </button>
          <button
            type="button"
            class="px-3 py-2 text-sm rounded-md border border-slate-100 text-slate-700"
            @click="showNewProduct = false"
          >
            Cancelar
          </button>
        </div>
      </form>

      <div class="flex items-center gap-4 mb-4">
        <input
          v-model="search"
          placeholder="Buscar por nome ou descrição"
          class="border border-slate-100 rounded-md p-2 text-sm w-72"
        />
        <label class="text-sm text-slate-600 flex items-center gap-2">
          <input v-model="showArchived" type="checkbox" />
          Mostrar arquivados
        </label>
        <button
          type="button"
          class="ml-auto text-sm text-woot-500"
          :disabled="loading"
          @click="fetchProducts"
        >
          Atualizar
        </button>
      </div>

      <p v-if="loading" class="text-sm text-slate-500">Carregando produtos…</p>
      <p v-else-if="!visibleProducts.length" class="text-sm text-slate-500">
        Nenhum produto encontrado.
      </p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr
            class="text-left text-xs uppercase text-slate-500 border-b border-slate-100"
          >
            <th class="py-2">Produto</th>
            <th class="py-2">Preços</th>
            <th class="py-2">Status</th>
            <th class="py-2 text-right">Ações</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="product in visibleProducts" :key="product.id">
            <tr class="border-b border-slate-50 align-top">
              <td class="py-3">
                <div class="text-slate-900">{{ product.name }}</div>
                <div class="text-xs text-slate-500">
                  {{ product.description }}
                </div>
                <div class="text-xs text-slate-400 mt-1">{{ product.id }}</div>
              </td>
              <td class="py-3">
                <div
                  v-if="!product.prices.length"
                  class="text-xs text-slate-400"
                >
                  Sem preço cadastrado
                </div>
                <div
                  v-for="price in product.prices"
                  :key="price.id"
                  class="text-xs"
                  :class="
                    price.active
                      ? 'text-slate-700'
                      : 'text-slate-400 line-through'
                  "
                >
                  {{ formatPrice(price) }}
                </div>
              </td>
              <td class="py-3">
                <span
                  class="text-xs px-2 py-1 rounded"
                  :class="
                    product.active
                      ? 'bg-emerald-25 text-emerald-700'
                      : 'bg-slate-25 text-slate-500'
                  "
                >
                  {{ product.active ? 'Ativo' : 'Arquivado' }}
                </span>
              </td>
              <td class="py-3 text-right whitespace-nowrap">
                <button
                  type="button"
                  class="text-woot-500 mr-3"
                  @click="startEdit(product)"
                >
                  Editar
                </button>
                <button
                  type="button"
                  class="text-woot-500 mr-3"
                  @click="startPricing(product)"
                >
                  Novo preço
                </button>
                <button
                  v-if="product.active"
                  type="button"
                  class="text-red-600"
                  @click="archiveProduct(product)"
                >
                  Arquivar
                </button>
                <button
                  v-else
                  type="button"
                  class="text-woot-500"
                  @click="reactivateProduct(product)"
                >
                  Reativar
                </button>
              </td>
            </tr>

            <tr v-if="editingId === product.id" :key="`${product.id}-edit`">
              <td colspan="4" class="pb-4">
                <form
                  class="p-3 rounded border border-slate-100 bg-slate-25"
                  @submit.prevent="submitEdit(product)"
                >
                  <div class="grid grid-cols-2 gap-3">
                    <label class="text-xs text-slate-600">
                      Nome
                      <input
                        v-model="editForm.name"
                        required
                        class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
                      />
                    </label>
                    <label class="text-xs text-slate-600">
                      Descrição
                      <input
                        v-model="editForm.description"
                        class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
                      />
                    </label>
                  </div>
                  <div class="flex gap-2 mt-3">
                    <button
                      type="submit"
                      :disabled="saving"
                      class="px-3 py-2 text-sm rounded-md bg-woot-500 text-white disabled:opacity-50"
                    >
                      Salvar
                    </button>
                    <button
                      type="button"
                      class="px-3 py-2 text-sm rounded-md border border-slate-100 text-slate-700"
                      @click="editingId = null"
                    >
                      Cancelar
                    </button>
                  </div>
                </form>
              </td>
            </tr>

            <tr v-if="pricingId === product.id" :key="`${product.id}-price`">
              <td colspan="4" class="pb-4">
                <form
                  class="p-3 rounded border border-slate-100 bg-slate-25"
                  @submit.prevent="submitPrice(product)"
                >
                  <p class="text-xs text-slate-500 mb-3">
                    O Stripe não permite editar um preço existente. Para mudar o
                    valor, crie um preço novo — o anterior continua valendo para
                    quem já assinou.
                  </p>
                  <div class="grid grid-cols-2 gap-3">
                    <label class="text-xs text-slate-600">
                      Valor (em reais)
                      <input
                        v-model="priceForm.unit_amount"
                        required
                        inputmode="decimal"
                        placeholder="199,90"
                        class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
                      />
                    </label>
                    <label class="text-xs text-slate-600">
                      Recorrência
                      <select
                        v-model="priceForm.recurring_interval"
                        class="mt-1 w-full border border-slate-100 rounded-md p-2 text-sm"
                      >
                        <option
                          v-for="(label, value) in INTERVAL_LABELS"
                          :key="value"
                          :value="value"
                        >
                          {{ label }}
                        </option>
                      </select>
                    </label>
                  </div>
                  <div class="flex gap-2 mt-3">
                    <button
                      type="submit"
                      :disabled="saving"
                      class="px-3 py-2 text-sm rounded-md bg-woot-500 text-white disabled:opacity-50"
                    >
                      Criar preço
                    </button>
                    <button
                      type="button"
                      class="px-3 py-2 text-sm rounded-md border border-slate-100 text-slate-700"
                      @click="pricingId = null"
                    >
                      Cancelar
                    </button>
                  </div>
                </form>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </template>
  </div>
</template>
