<script setup>
import { ref, computed, onMounted } from 'vue';

const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const DURATION_LABELS = {
  once: 'Uma vez',
  repeating: 'Por alguns meses',
  forever: 'Para sempre',
};

const coupons = ref([]);
const products = ref([]);
const loading = ref(false);
const saving = ref(false);
const error = ref(null);
const showForm = ref(false);
const form = ref({
  name: '',
  kind: 'percent',
  percent_off: 10,
  amount_off: '',
  duration: 'once',
  duration_in_months: 3,
  product_ids: [],
  max_redemptions: '',
});

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
    coupons.value = body.coupons || [];
    products.value = body.products || [];
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  if (props.componentData.configured) fetchData();
});

const formatAmount = (amount, currency) =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: (currency || 'brl').toUpperCase(),
  }).format((amount || 0) / 100);

const discountLabel = coupon =>
  coupon.percent_off
    ? `${coupon.percent_off}%`
    : formatAmount(coupon.amount_off, coupon.currency);

const durationLabel = coupon => {
  if (coupon.duration === 'repeating') {
    return `${DURATION_LABELS.repeating} (${coupon.duration_in_months})`;
  }
  return DURATION_LABELS[coupon.duration] || coupon.duration;
};

const productNames = coupon => {
  if (!coupon.product_ids?.length) return 'Toda a fatura';
  return coupon.product_ids
    .map(id => products.value.find(product => product.id === id)?.name || id)
    .join(', ');
};

const openForm = () => {
  showForm.value = true;
  error.value = null;
  form.value = {
    name: '',
    kind: 'percent',
    percent_off: 10,
    amount_off: '',
    duration: 'once',
    duration_in_months: 3,
    product_ids: [],
    max_redemptions: '',
  };
};

const canSave = computed(
  () =>
    form.value.name &&
    (form.value.kind === 'percent'
      ? Number(form.value.percent_off) > 0
      : Number(form.value.amount_off) > 0)
);

const submit = async () => {
  saving.value = true;
  error.value = null;
  try {
    await request(props.componentData.coupons_url, {
      method: 'POST',
      body: {
        name: form.value.name,
        // Stripe refuses a coupon carrying both, so only the chosen one is sent.
        percent_off:
          form.value.kind === 'percent' ? form.value.percent_off : null,
        amount_off: form.value.kind === 'amount' ? form.value.amount_off : null,
        duration: form.value.duration,
        duration_in_months: form.value.duration_in_months,
        product_ids: form.value.product_ids,
        max_redemptions: form.value.max_redemptions,
      },
    });
    showForm.value = false;
    await fetchData();
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

const removeCoupon = async coupon => {
  const message = `Excluir o cupom "${coupon.name}"? Quem já recebeu o desconto continua com ele; o cupom apenas deixa de ser aplicável em novas assinaturas e faturas.`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;

  try {
    await request(`${props.componentData.coupons_url}/${coupon.id}`, {
      method: 'DELETE',
    });
    await fetchData();
  } catch (e) {
    error.value = e.message;
  }
};
</script>

<template>
  <div class="p-6">
    <div class="mb-6 flex items-start justify-between gap-4">
      <div>
        <h1 class="text-xl font-medium text-slate-900">Cupons</h1>
        <p class="text-sm text-slate-500 mt-1">
          Descontos que podem ser aplicados ao criar uma assinatura ou uma
          fatura. Um cupom restrito a produtos desconta apenas aquelas linhas.
        </p>
      </div>
      <button
        v-if="componentData.configured"
        type="button"
        class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm whitespace-nowrap"
        @click="openForm"
      >
        Novo cupom
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
      <div v-if="error" class="p-3 mb-4 rounded bg-red-25 text-sm text-red-700">
        {{ error }}
      </div>

      <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-slate-500 border-b border-slate-100">
            <th class="py-2">Cupom</th>
            <th class="py-2">Desconto</th>
            <th class="py-2">Duração</th>
            <th class="py-2">Aplica em</th>
            <th class="py-2 text-right">Usos</th>
            <th class="py-2 text-right">Ação</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="coupon in coupons"
            :key="coupon.id"
            class="border-b border-slate-50"
          >
            <td class="py-3">
              <div class="text-slate-900">{{ coupon.name || coupon.id }}</div>
              <div class="text-xs text-slate-400">{{ coupon.id }}</div>
            </td>
            <td class="py-3 text-slate-700">{{ discountLabel(coupon) }}</td>
            <td class="py-3 text-slate-700">{{ durationLabel(coupon) }}</td>
            <td class="py-3 text-slate-700">{{ productNames(coupon) }}</td>
            <td class="py-3 text-right text-slate-700">
              {{ coupon.times_redeemed }}
              <span v-if="coupon.max_redemptions" class="text-slate-400">
                / {{ coupon.max_redemptions }}
              </span>
            </td>
            <td class="py-3 text-right">
              <button
                type="button"
                class="text-red-600 text-xs"
                @click="removeCoupon(coupon)"
              >
                Excluir
              </button>
            </td>
          </tr>
          <tr v-if="!coupons.length">
            <td colspan="6" class="py-6 text-center text-slate-500">
              Nenhum cupom cadastrado.
            </td>
          </tr>
        </tbody>
      </table>
    </template>

    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    >
      <div
        class="bg-white rounded-lg shadow-lg w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto"
      >
        <h2 class="text-lg font-medium text-slate-900">Novo cupom</h2>

        <label class="block mt-4 text-sm text-slate-600">
          Nome
          <input
            v-model="form.name"
            type="text"
            placeholder="Ex: Desconto parceiro"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          />
        </label>

        <div class="grid grid-cols-2 gap-3 mt-3">
          <label class="block text-sm text-slate-600">
            Tipo
            <select
              v-model="form.kind"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            >
              <option value="percent">Percentual</option>
              <option value="amount">Valor fixo</option>
            </select>
          </label>
          <label
            v-if="form.kind === 'percent'"
            class="block text-sm text-slate-600"
          >
            Percentual (%)
            <input
              v-model.number="form.percent_off"
              type="number"
              min="1"
              max="100"
              step="0.01"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
          <label v-else class="block text-sm text-slate-600">
            Valor (R$)
            <input
              v-model="form.amount_off"
              type="number"
              min="0"
              step="0.01"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
        </div>

        <div class="grid grid-cols-2 gap-3 mt-3">
          <label class="block text-sm text-slate-600">
            Duração
            <select
              v-model="form.duration"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            >
              <option value="once">Uma vez</option>
              <option value="repeating">Por alguns meses</option>
              <option value="forever">Para sempre</option>
            </select>
          </label>
          <label
            v-if="form.duration === 'repeating'"
            class="block text-sm text-slate-600"
          >
            Meses
            <input
              v-model.number="form.duration_in_months"
              type="number"
              min="1"
              class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
            />
          </label>
        </div>

        <label class="block mt-3 text-sm text-slate-600">
          Aplica em (opcional)
          <select
            v-model="form.product_ids"
            multiple
            size="4"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          >
            <option
              v-for="product in products"
              :key="product.id"
              :value="product.id"
            >
              {{ product.name }}
            </option>
          </select>
          <span class="text-xs text-slate-400">
            Sem seleção, o desconto vale para a fatura inteira.
          </span>
        </label>

        <label class="block mt-3 text-sm text-slate-600">
          Limite de usos (opcional)
          <input
            v-model="form.max_redemptions"
            type="number"
            min="1"
            class="mt-1 w-full border border-slate-200 rounded px-2 py-1.5 text-sm"
          />
        </label>

        <p v-if="error" class="text-sm text-red-600 mt-3">{{ error }}</p>

        <div class="flex justify-end gap-2 mt-5">
          <button
            type="button"
            class="px-3 py-1.5 text-sm text-slate-600"
            :disabled="saving"
            @click="showForm = false"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
            :disabled="saving || !canSave"
            @click="submit"
          >
            {{ saving ? 'Criando…' : 'Criar cupom' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
