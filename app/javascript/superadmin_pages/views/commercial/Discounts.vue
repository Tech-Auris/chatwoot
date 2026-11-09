<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const discounts = ref([]);
const products = ref([]);
const loading = ref(false);
const saving = ref(false);
const error = ref(null);

const emptyForm = () => ({
  id: null,
  name: '',
  percent: '',
  scope: 'order',
  stripe_product_ids: [],
  expires_with_reservation: false,
  active: true,
});
const form = ref(null);
const productSearch = ref('');

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

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const body = await request(props.componentData.data_url);
    discounts.value = body.discounts || [];
    products.value = body.products || [];
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);

// A product the discount points at may have been archived in Stripe since;
// it still shows by id so the scope never silently looks empty.
const productName = id =>
  products.value.find(product => product.id === id)?.name || id;

const formatPercent = percent => `${Number(percent)}%`;

const newDiscount = () => {
  form.value = emptyForm();
};

const editDiscount = discount => {
  form.value = {
    ...discount,
    scope: discount.stripe_product_ids.length ? 'products' : 'order',
    stripe_product_ids: [...discount.stripe_product_ids],
  };
};

const availableProducts = computed(() => {
  if (!form.value) return [];
  const term = productSearch.value.trim().toLowerCase();
  return products.value.filter(
    product =>
      !form.value.stripe_product_ids.includes(product.id) &&
      (!term || product.name.toLowerCase().includes(term))
  );
});

const addProduct = product => {
  form.value.stripe_product_ids.push(product.id);
  productSearch.value = '';
};

const removeProduct = id => {
  form.value.stripe_product_ids = form.value.stripe_product_ids.filter(
    productId => productId !== id
  );
};

const canSave = computed(
  () =>
    form.value &&
    form.value.name.trim() &&
    Number(form.value.percent) > 0 &&
    (form.value.scope === 'order' || form.value.stripe_product_ids.length) &&
    !saving.value
);

const save = async () => {
  saving.value = true;
  error.value = null;
  const { id, scope, ...fields } = form.value;
  const discount = {
    name: fields.name,
    percent: fields.percent,
    stripe_product_ids: scope === 'products' ? fields.stripe_product_ids : [],
    expires_with_reservation: fields.expires_with_reservation,
    active: fields.active,
  };
  try {
    const url = id
      ? `${props.componentData.discounts_url}/${id}`
      : props.componentData.discounts_url;
    await request(url, { method: id ? 'PATCH' : 'POST', body: { discount } });
    form.value = null;
    await fetchData();
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="w-full px-6 py-6 bg-n-background">
    <div class="max-w-6xl mx-auto flex flex-col gap-5">
      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-1">
          <h1 class="text-xl font-semibold text-n-slate-12">Descontos</h1>
          <p class="text-sm text-n-slate-11">
            Descontos que o vendedor pode adicionar na proposta. Sem produtos,
            valem para o pedido todo; com produtos, só para esses itens.
          </p>
        </div>
        <button
          type="button"
          class="px-3 py-2 rounded bg-woot-500 text-white text-sm whitespace-nowrap"
          @click="newDiscount"
        >
          + Novo desconto
        </button>
      </div>

      <p v-if="loading" class="text-sm text-n-slate-11">Carregando…</p>
      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>

      <section
        v-if="form"
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl p-5 flex flex-col gap-4"
      >
        <h2 class="text-base font-semibold text-n-slate-12">
          {{ form.id ? 'Editar desconto' : 'Novo desconto' }}
        </h2>

        <div class="flex gap-3">
          <label class="flex-[2] text-sm text-n-slate-11">
            Nome
            <input
              v-model="form.name"
              type="text"
              placeholder="Ex.: Indicação"
              class="mt-1 w-full border border-slate-200 rounded px-3 py-2 text-sm"
            />
          </label>
          <label class="flex-1 text-sm text-n-slate-11">
            Percentual
            <input
              v-model="form.percent"
              type="number"
              min="0.01"
              max="100"
              step="0.01"
              class="mt-1 w-full border border-slate-200 rounded px-3 py-2 text-sm"
            />
          </label>
        </div>

        <div class="flex flex-col gap-2 text-sm text-n-slate-12">
          <span class="text-n-slate-11">Aplica em</span>
          <div class="flex gap-4">
            <label class="flex items-center gap-2">
              <input v-model="form.scope" type="radio" value="order" />
              Pedido todo
            </label>
            <label class="flex items-center gap-2">
              <input v-model="form.scope" type="radio" value="products" />
              Produtos específicos (avulsos)
            </label>
          </div>

          <div v-if="form.scope === 'products'" class="flex flex-col gap-2">
            <div class="flex flex-wrap gap-1">
              <span
                v-for="id in form.stripe_product_ids"
                :key="id"
                class="inline-flex items-center gap-1 bg-slate-100 rounded px-2 py-0.5 text-xs"
              >
                {{ productName(id) }}
                <button
                  type="button"
                  class="text-n-ruby-11"
                  @click="removeProduct(id)"
                >
                  ✕
                </button>
              </span>
            </div>
            <input
              v-model="productSearch"
              type="search"
              placeholder="Buscar produto do Stripe…"
              class="w-full border border-slate-200 rounded px-3 py-2 text-sm"
            />
            <ul
              v-if="productSearch"
              class="max-h-48 overflow-y-auto border border-slate-200 rounded"
            >
              <li v-for="product in availableProducts" :key="product.id">
                <button
                  type="button"
                  class="w-full text-left px-3 py-1.5 text-sm !text-slate-700 !bg-transparent hover:!bg-slate-100"
                  @click="addProduct(product)"
                >
                  {{ product.name }}
                </button>
              </li>
              <li
                v-if="!availableProducts.length"
                class="px-3 py-1.5 text-sm text-slate-500"
              >
                Nenhum produto avulso para "{{ productSearch }}".
              </li>
            </ul>
          </div>
        </div>

        <div class="flex gap-6 text-sm text-n-slate-12">
          <label class="flex items-center gap-2">
            <input v-model="form.expires_with_reservation" type="checkbox" />
            Vence com a reserva
          </label>
          <label class="flex items-center gap-2">
            <input v-model="form.active" type="checkbox" />
            Ativo
          </label>
        </div>

        <div class="flex gap-2">
          <button
            type="button"
            class="px-3 py-2 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="!canSave"
            @click="save"
          >
            {{ saving ? 'Salvando…' : 'Salvar' }}
          </button>
          <button
            type="button"
            class="px-3 py-2 rounded text-sm text-n-slate-11"
            @click="form = null"
          >
            Cancelar
          </button>
        </div>
      </section>

      <section
        v-if="!loading"
        class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl p-5"
      >
        <p v-if="!discounts.length" class="text-sm text-n-slate-11">
          Nenhum desconto cadastrado.
        </p>
        <table v-else class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs text-n-slate-11">
              <th class="py-2">Nome</th>
              <th class="py-2">%</th>
              <th class="py-2">Aplica em</th>
              <th class="py-2">Vence com a reserva</th>
              <th class="py-2">Ativo</th>
              <th />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="discount in discounts"
              :key="discount.id"
              class="border-t border-n-container align-top"
              :class="{ 'opacity-50': !discount.active }"
            >
              <td class="py-2 text-n-slate-12">{{ discount.name }}</td>
              <td class="py-2">{{ formatPercent(discount.percent) }}</td>
              <td class="py-2">
                <span v-if="!discount.stripe_product_ids.length">
                  Pedido todo
                </span>
                <span
                  v-for="id in discount.stripe_product_ids"
                  :key="id"
                  class="inline-block bg-slate-100 rounded px-2 py-0.5 mr-1 mb-1 text-xs"
                >
                  {{ productName(id) }}
                </span>
              </td>
              <td class="py-2">
                {{ discount.expires_with_reservation ? 'Sim' : 'Não' }}
              </td>
              <td class="py-2">{{ discount.active ? 'Sim' : 'Não' }}</td>
              <td class="py-2 text-right">
                <button
                  type="button"
                  class="text-xs text-woot-500"
                  @click="editDiscount(discount)"
                >
                  Editar
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
  </div>
</template>
