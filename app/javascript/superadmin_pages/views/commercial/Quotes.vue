<script setup>
import { ref, computed, onMounted, watch } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const prospectTerm = ref('');
const prospectResults = ref([]);
const selectedProspect = ref(null);
const searching = ref(false);

const prices = ref([]);
const coupons = ref([]);
const meetingDiscountPercent = ref(10);

const cart = ref([]);
const meetingDiscount = ref(false);
const couponId = ref('');
const totals = ref({ subtotal: 0, discount: 0, total: 0, summary: null });

const loading = ref(false);
const saving = ref(false);
const error = ref(null);
const savedQuote = ref(null);

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

const formatAmount = (amount, currency = 'brl') =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: currency.toUpperCase(),
  }).format((amount || 0) / 100);

const fetchCatalog = async () => {
  loading.value = true;
  error.value = null;
  try {
    const body = await request(props.componentData.data_url);
    prices.value = body.prices || [];
    coupons.value = body.coupons || [];
    meetingDiscountPercent.value = body.meeting_discount_percent ?? 10;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  if (props.componentData.stripe_configured) fetchCatalog();
});

// Typing runs against the pipeline cached on the server; a short debounce keeps
// a fast typist from firing a request per keystroke.
let searchTimer = null;
const searchProspects = () => {
  clearTimeout(searchTimer);
  if (prospectTerm.value.trim().length < 2) {
    prospectResults.value = [];
    return;
  }

  searchTimer = setTimeout(async () => {
    searching.value = true;
    try {
      const body = await request(
        `${props.componentData.prospects_url}?q=${encodeURIComponent(prospectTerm.value)}`
      );
      prospectResults.value = body.prospects || [];
    } catch (e) {
      error.value = e.message;
    } finally {
      searching.value = false;
    }
  }, 300);
};

const selectProspect = prospect => {
  selectedProspect.value = prospect;
  prospectResults.value = [];
  prospectTerm.value = prospect.clinic_name || prospect.name;
};

const priceLabel = price => {
  const name = price.product_name || price.id;
  const interval = price.recurring_interval
    ? ` / ${price.recurring_interval}`
    : '';
  return `${name} — ${formatAmount(price.unit_amount, price.currency)}${interval}`;
};

const addToCart = price => {
  const existing = cart.value.find(item => item.stripe_price_id === price.id);
  if (existing) {
    existing.quantity += 1;
    return;
  }

  cart.value.push({
    stripe_price_id: price.id,
    stripe_product_id: price.product_id,
    name: price.product_name || price.id,
    unit_amount: price.unit_amount,
    currency: price.currency,
    recurring_interval: price.recurring_interval,
    quantity: 1,
    kind: price.recurring_interval ? 'plan' : 'addon',
  });
};

const removeFromCart = index => {
  cart.value.splice(index, 1);
};

const refreshTotals = async () => {
  if (!cart.value.length) {
    totals.value = { subtotal: 0, discount: 0, total: 0, summary: null };
    return;
  }

  try {
    totals.value = await request(props.componentData.preview_url, {
      method: 'POST',
      body: {
        items: cart.value,
        meeting_discount: meetingDiscount.value,
        coupon_id: couponId.value,
      },
    });
  } catch (e) {
    error.value = e.message;
  }
};

watch([cart, meetingDiscount, couponId], refreshTotals, { deep: true });

const canSave = computed(
  () => selectedProspect.value && cart.value.length && !saving.value
);

const saveQuote = async () => {
  saving.value = true;
  error.value = null;
  try {
    const body = await request(props.componentData.quotes_url, {
      method: 'POST',
      body: {
        clickup_task_id: selectedProspect.value.task_id,
        items: cart.value,
        meeting_discount: meetingDiscount.value,
        coupon_id: couponId.value,
      },
    });
    savedQuote.value = body.quote;
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

const startOver = () => {
  savedQuote.value = null;
  cart.value = [];
  meetingDiscount.value = false;
  couponId.value = '';
  selectedProspect.value = null;
  prospectTerm.value = '';
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-medium text-slate-900">Montar plano</h1>
      <p class="text-sm text-slate-500 mt-1">
        Escolha o cliente no pipeline, monte o carrinho com os planos e
        adicionais e confira o total. A reserva e o link para o cliente vêm na
        próxima etapa.
      </p>
    </div>

    <div
      v-if="
        !componentData.stripe_configured || !componentData.clickup_configured
      "
      class="p-4 rounded border border-amber-100 bg-amber-25 text-sm text-amber-700"
    >
      Falta configurar
      <span v-if="!componentData.stripe_configured">o Stripe</span>
      <span
        v-if="
          !componentData.stripe_configured && !componentData.clickup_configured
        "
      >
        e
      </span>
      <span v-if="!componentData.clickup_configured">o ClickUp</span>
      em Settings para liberar esta tela.
    </div>

    <template v-else>
      <div v-if="error" class="p-3 mb-4 rounded bg-red-25 text-sm text-red-700">
        {{ error }}
      </div>

      <div v-if="savedQuote" class="border border-slate-100 rounded-lg p-5">
        <h2 class="text-sm font-medium text-slate-800">Proposta criada</h2>
        <p class="text-sm text-slate-600 mt-2">
          {{ savedQuote.prospect_name }} —
          <strong>{{ formatAmount(savedQuote.total_amount) }}</strong>
          <span v-if="savedQuote.discount_summary" class="text-slate-500">
            ({{ savedQuote.discount_summary }})
          </span>
        </p>
        <p class="text-xs text-slate-500 mt-2">
          Código de acesso do cliente:
          <strong>{{ savedQuote.access_code }}</strong>
        </p>
        <button
          type="button"
          class="mt-4 px-3 py-1.5 rounded bg-woot-500 text-white text-sm"
          @click="startOver"
        >
          Montar outra
        </button>
      </div>

      <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 flex flex-col gap-6">
          <div class="border border-slate-100 rounded-lg p-5">
            <h2 class="text-sm font-medium text-slate-800 mb-3">1. Cliente</h2>
            <input
              v-model="prospectTerm"
              type="text"
              placeholder="Buscar por nome, e-mail ou telefone…"
              class="w-full border border-slate-200 rounded px-3 py-2 text-sm"
              @input="searchProspects"
            />
            <p v-if="searching" class="text-xs text-slate-500 mt-2">
              Buscando…
            </p>

            <ul
              v-if="prospectResults.length"
              class="mt-2 border border-slate-100 rounded divide-y divide-slate-50"
            >
              <li v-for="prospect in prospectResults" :key="prospect.task_id">
                <button
                  type="button"
                  class="w-full text-left px-3 py-2 hover:bg-slate-25"
                  @click="selectProspect(prospect)"
                >
                  <span class="text-sm text-slate-900">
                    {{ prospect.clinic_name || prospect.name }}
                  </span>
                  <span class="text-xs text-slate-500 ml-2">
                    {{ prospect.email }} {{ prospect.phone }}
                  </span>
                  <span class="text-xs text-slate-400 ml-2">
                    {{ prospect.status }}
                  </span>
                </button>
              </li>
            </ul>

            <p v-if="selectedProspect" class="text-sm text-slate-700 mt-3">
              Selecionado:
              <strong>
                {{ selectedProspect.clinic_name || selectedProspect.name }}
              </strong>
              <span class="text-xs text-slate-400 ml-1">
                ({{ selectedProspect.task_id }})
              </span>
            </p>
          </div>

          <div class="border border-slate-100 rounded-lg p-5">
            <h2 class="text-sm font-medium text-slate-800 mb-3">
              2. Planos e adicionais
            </h2>
            <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>
            <ul v-else class="divide-y divide-slate-50">
              <li
                v-for="price in prices"
                :key="price.id"
                class="flex items-center justify-between py-2"
              >
                <span class="text-sm text-slate-700">
                  {{ priceLabel(price) }}
                </span>
                <button
                  type="button"
                  class="px-2.5 py-1 rounded bg-woot-500 text-white text-xs"
                  @click="addToCart(price)"
                >
                  Adicionar
                </button>
              </li>
            </ul>
          </div>
        </div>

        <div class="border border-slate-100 rounded-lg p-5 h-fit">
          <h2 class="text-sm font-medium text-slate-800 mb-3">3. Carrinho</h2>

          <p v-if="!cart.length" class="text-sm text-slate-500">
            Nenhum item ainda.
          </p>
          <ul v-else class="divide-y divide-slate-50">
            <li
              v-for="(item, index) in cart"
              :key="item.stripe_price_id"
              class="py-2"
            >
              <div class="flex items-start justify-between gap-2">
                <span class="text-sm text-slate-800">{{ item.name }}</span>
                <button
                  type="button"
                  class="text-xs text-red-600"
                  @click="removeFromCart(index)"
                >
                  Remover
                </button>
              </div>
              <div class="flex items-center gap-2 mt-1">
                <input
                  v-model.number="item.quantity"
                  type="number"
                  min="1"
                  class="w-16 border border-slate-200 rounded px-2 py-1 text-sm"
                />
                <span class="text-xs text-slate-500">
                  × {{ formatAmount(item.unit_amount, item.currency) }}
                </span>
              </div>
            </li>
          </ul>

          <label class="flex items-center gap-2 mt-4 text-sm text-slate-700">
            <input v-model="meetingDiscount" type="checkbox" />
            Desconto da reunião ({{ meetingDiscountPercent }}%)
          </label>

          <label class="block mt-3 text-sm text-slate-600">
            Cupom
            <select
              v-model="couponId"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            >
              <option value="">— sem cupom —</option>
              <option
                v-for="coupon in coupons"
                :key="coupon.id"
                :value="coupon.id"
              >
                {{ coupon.name || coupon.id }}
              </option>
            </select>
          </label>

          <div class="mt-4 pt-4 border-t border-slate-100 text-sm">
            <div class="flex justify-between text-slate-600">
              <span>Subtotal</span>
              <span>{{ formatAmount(totals.subtotal) }}</span>
            </div>
            <div
              v-if="totals.discount"
              class="flex justify-between text-emerald-700 mt-1"
            >
              <span>Desconto</span>
              <span>− {{ formatAmount(totals.discount) }}</span>
            </div>
            <p
              v-if="totals.summary"
              class="text-xs text-slate-500 mt-1 text-right"
            >
              {{ totals.summary }}
            </p>
            <div
              class="flex justify-between text-slate-900 font-medium mt-2 text-base"
            >
              <span>Total</span>
              <span>{{ formatAmount(totals.total) }}</span>
            </div>
          </div>

          <button
            type="button"
            class="mt-5 w-full px-3 py-2 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="!canSave"
            @click="saveQuote"
          >
            {{ saving ? 'Salvando…' : 'Salvar proposta' }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
