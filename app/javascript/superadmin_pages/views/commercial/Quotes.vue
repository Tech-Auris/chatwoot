<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import {
  buildReservationMessage,
  isReservationMessageAvailable,
} from '../../helpers/commercialMessage';

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
const reservedUntil = ref('');
const reserving = ref(false);
const reservation = ref(null);
const copied = ref(false);

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

// A coupon says what it takes off, next to its name: the team picks by the
// discount, and two coupons can read the same by name alone.
const couponLabel = coupon => {
  const name = coupon.name || coupon.id;
  if (coupon.percent_off) return `${name} — ${coupon.percent_off}%`;
  if (coupon.amount_off) return `${name} — ${formatAmount(coupon.amount_off)}`;
  return name;
};

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

// Same shape the product picker uses: close the results only when
// focus lands outside the container so a click on a row is not
// dismissed mid-selection.
const onProspectPickerFocusOut = event => {
  const next = event.relatedTarget;
  if (!next || !event.currentTarget.contains(next)) {
    prospectResults.value = [];
  }
};

// The seller searches by the deal's own name — the clinic name is filled in
// later by the prospect on the public form, so a row must lead with the
// name the seller knows and carry the rest as context for disambiguation.
const formatBrPhone = raw => {
  if (!raw) return '';
  const digits = String(raw).replace(/\D/g, '');
  if (digits.length === 13 && digits.startsWith('55')) {
    return `+55 (${digits.slice(2, 4)}) ${digits.slice(4, 9)}-${digits.slice(9)}`;
  }
  if (digits.length === 11) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
  }
  if (digits.length === 10) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  }
  return raw;
};

const formatProspectRow = prospect => {
  const parts = [
    prospect.name,
    prospect.status,
    prospect.email,
    formatBrPhone(prospect.phone),
    prospect.clinic_name,
  ]
    .map(value => (value == null ? '' : String(value).trim()))
    .filter(value => value.length);

  return parts.join(' / ');
};

// The catalogue is read while somebody is on the phone, and the seller
// speaks the product first ("Plataforma Auris") and only then the period
// ("mensal / semestral / anual"). Match that flow: an autocomplete field
// that opens a floating dropdown of every product on focus, grouped with
// its prices under each; typing filters both the name and the description.
const productSearch = ref('');
const productDropdownOpen = ref(false);

const openProductDropdown = () => {
  productDropdownOpen.value = true;
};

// `focusout` bubbles up from any focusable inside the container; close
// only when the focus lands outside so a click on a price row does not
// dismiss the list mid-selection.
const onProductPickerFocusOut = event => {
  const next = event.relatedTarget;
  if (!next || !event.currentTarget.contains(next)) {
    productDropdownOpen.value = false;
  }
};

// The order the server sends prices in is most-sold first; keep that,
// but preserve product ordering by first-appearance so the top of the
// list is what the team actually sells the most.
const productList = computed(() => {
  const byId = new Map();
  prices.value.forEach(price => {
    if (!byId.has(price.product_id)) {
      byId.set(price.product_id, {
        id: price.product_id,
        name: price.product_name,
        description: price.product_description,
        prices: [],
      });
    }
    byId.get(price.product_id).prices.push(price);
  });
  return [...byId.values()];
});

const filteredProducts = computed(() => {
  const query = productSearch.value.trim().toLowerCase();
  if (!query) return productList.value;
  return productList.value.filter(product => {
    const haystack =
      `${product.name || ''} ${product.description || ''}`.toLowerCase();
    return haystack.includes(query);
  });
});

// How Stripe labels the price beside the amount — the seller reads this
// out loud, so it matches how the plan is spoken: "/mês", "a cada 6
// meses", "/ano", or nothing when the item is charged once.
const PERIOD_SUFFIX = {
  monthly: '/mês',
  semiannual: ' a cada 6 meses',
  annual: '/ano',
  one_off: '',
};

const pricePeriodSuffix = price => {
  if (price.billing_period in PERIOD_SUFFIX) {
    return PERIOD_SUFFIX[price.billing_period];
  }
  return price.recurring_interval ? `/${price.recurring_interval}` : '';
};

// A tiered Stripe price has no single unit amount — the number depends
// on the quantity band. Fall back to the first-tier price and prefix
// "A partir de " so the seller reads the same wording Stripe uses.
const priceAmountLabel = price => {
  const amount = price.tiered ? price.starting_amount : price.unit_amount;
  const label = `${formatAmount(amount, price.currency)}${pricePeriodSuffix(price)}`;
  return price.tiered ? `A partir de ${label}` : label;
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
    // `billing_period` on the plan item is what the backend uses to know
    // whether the proposal is monthly/semiannual/annual — the routing
    // between Stripe (subscription) and AsaaS (instalments) reads that
    // off the quote and the `recurring_interval` alone doesn't tell
    // monthly from semiannual (both are "month" with different counts).
    billing_period: price.billing_period,
    quantity: 1,
    kind: price.category || (price.recurring_interval ? 'plan' : 'addon'),
    // Tier data flows through so the cart can price the row at the
    // right band as the seller edits the quantity; the payload
    // transforms `unit_amount` back into a flat effective price so the
    // backend calculator (which just multiplies) still lands on the
    // same subtotal.
    tiered: price.tiered === true,
    tiers: price.tiers || null,
    tiers_mode: price.tiers_mode || null,
  });
};

// Sums the line at the tier the current quantity lands in. `graduated`
// charges each band separately (a Stripe classic — the first 8 at R$59,
// the next 21 at R$29, and so on); `volume` charges the whole quantity
// at the band the total falls in.
const computeTierLineTotal = item => {
  const qty = Math.max(1, Number(item.quantity) || 1);
  const tiers = Array.isArray(item.tiers) ? item.tiers : [];
  if (!tiers.length) return 0;

  if (item.tiers_mode === 'volume') {
    const tier =
      tiers.find(
        t => t.up_to === null || t.up_to === undefined || qty <= t.up_to
      ) || tiers[tiers.length - 1];
    return (
      qty * (Number(tier.unit_amount) || 0) + (Number(tier.flat_amount) || 0)
    );
  }

  // `.reduce` here plays the role of a break-on-empty loop — once every
  // unit has been priced, later tiers add nothing.
  return tiers.reduce(
    (acc, tier) => {
      if (acc.remaining <= 0) return acc;
      const cap =
        tier.up_to === null || tier.up_to === undefined ? Infinity : tier.up_to;
      const bandSize = cap - acc.previousCap;
      const take = Math.min(bandSize, acc.remaining);
      return {
        remaining: acc.remaining - take,
        total:
          acc.total +
          take * (Number(tier.unit_amount) || 0) +
          (Number(tier.flat_amount) || 0),
        previousCap: cap,
      };
    },
    { remaining: qty, total: 0, previousCap: 0 }
  ).total;
};

const cartItemLineTotal = item => {
  if (item.tiered) return computeTierLineTotal(item);
  const qty = Math.max(1, Number(item.quantity) || 1);
  return (Number(item.unit_amount) || 0) * qty;
};

// The backend calculator sums `unit_amount * quantity`, so a tiered
// item ships with the effective per-unit price (line total ÷ qty) and
// the original quantity, keeping the persisted row readable. Rounding
// can drift graduated totals by a handful of cents; Stripe applies
// tiers exactly at checkout time.
const payloadItems = () =>
  cart.value.map(item => {
    if (!item.tiered) return item;
    const qty = Math.max(1, Number(item.quantity) || 1);
    const line = computeTierLineTotal(item);
    return { ...item, unit_amount: Math.round(line / qty), quantity: qty };
  });

const selectPrice = price => {
  addToCart(price);
  productSearch.value = '';
  productDropdownOpen.value = false;
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
        items: payloadItems(),
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
        items: payloadItems(),
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

// Holding the proposal writes the deadline onto the ClickUp task; a failure
// there is reported instead of swallowed, because the seller would otherwise
// believe the task carries the date.
const reserve = async () => {
  reserving.value = true;
  error.value = null;
  try {
    const body = await request(
      `${props.componentData.quotes_url}/${savedQuote.value.id}/reserve`,
      { method: 'POST', body: { reserved_until: reservedUntil.value } }
    );
    reservation.value = body;
    savedQuote.value = body.quote;
  } catch (e) {
    error.value = e.message;
  } finally {
    reserving.value = false;
  }
};

const copyLink = async () => {
  await navigator.clipboard.writeText(savedQuote.value.public_url);
  copied.value = true;
  setTimeout(() => {
    copied.value = false;
  }, 2000);
};

// Same visual affordance as `copyLink`, but writes the composed
// WhatsApp message the sales team pastes into the prospect's chat.
const messageCopied = ref(false);
const copyMessage = async () => {
  await navigator.clipboard.writeText(
    buildReservationMessage(savedQuote.value)
  );
  messageCopied.value = true;
  setTimeout(() => {
    messageCopied.value = false;
  }, 2000);
};
const canCopyMessage = computed(() =>
  isReservationMessageAvailable(savedQuote.value)
);

const startOver = () => {
  savedQuote.value = null;
  reservation.value = null;
  reservedUntil.value = '';
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
      class="p-4 rounded border border-yellow-100 bg-yellow-50 text-sm text-yellow-700"
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
      <div v-if="error" class="p-3 mb-4 rounded bg-red-50 text-sm text-red-700">
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
        <!-- Lead context on the confirmation panel so the seller can
             double-check the recipient without opening the ClickUp task.
             Fields that come blank from ClickUp simply skip their row. -->
        <ul class="mt-2 text-xs text-slate-500 space-y-0.5">
          <li v-if="savedQuote.company_name">
            <span class="text-slate-400">Clínica:</span>
            {{ savedQuote.company_name }}
          </li>
          <li v-if="savedQuote.prospect_email">
            <span class="text-slate-400">E-mail:</span>
            {{ savedQuote.prospect_email }}
          </li>
          <li v-if="savedQuote.prospect_phone">
            <span class="text-slate-400">WhatsApp:</span>
            {{ savedQuote.prospect_phone }}
          </li>
        </ul>

        <div class="mt-5 pt-5 border-t border-slate-100">
          <h3 class="text-sm font-medium text-slate-800">Reserva</h3>
          <p class="text-xs text-slate-500 mt-1">
            A data vai para o vencimento da tarefa no ClickUp, junto com a
            etiqueta “reserva”.
          </p>

          <div class="flex flex-wrap items-end gap-3 mt-3">
            <label class="text-sm text-slate-600">
              Vencimento da reserva
              <input
                v-model="reservedUntil"
                type="datetime-local"
                class="mt-1 block border border-slate-200 rounded px-2 py-1.5 text-sm"
              />
            </label>
            <button
              type="button"
              class="px-3 py-1.5 rounded bg-woot-500 text-white text-sm disabled:opacity-40"
              :disabled="!reservedUntil || reserving"
              @click="reserve"
            >
              {{
                reserving
                  ? 'Reservando…'
                  : savedQuote.reserved_until
                    ? 'Renovar reserva'
                    : 'Reservar'
              }}
            </button>
          </div>

          <p
            v-if="reservation && !reservation.clickup_synced"
            class="mt-3 text-xs text-yellow-700"
          >
            Reserva registrada, mas o ClickUp não foi atualizado:
            {{ reservation.clickup_error }}. Ajuste a data na tarefa à mão.
          </p>
        </div>

        <div
          v-if="savedQuote.public_url"
          class="mt-5 pt-5 border-t border-slate-100"
        >
          <h3 class="text-sm font-medium text-slate-800">Link do cliente</h3>
          <div class="flex flex-wrap items-start gap-4 mt-3">
            <img
              v-if="savedQuote.qr_code"
              :src="savedQuote.qr_code"
              alt="QR code da proposta"
              class="w-32 h-32 border border-slate-100 rounded"
            />
            <div class="flex-1 min-w-[16rem]">
              <input
                :value="savedQuote.public_url"
                readonly
                class="w-full border border-slate-200 rounded px-2 py-1.5 text-xs text-slate-600"
              />
              <div class="mt-2 flex flex-wrap gap-2">
                <button
                  type="button"
                  class="px-3 py-1.5 rounded bg-slate-100 text-slate-700 text-xs"
                  @click="copyLink"
                >
                  {{ copied ? 'Copiado!' : 'Copiar link' }}
                </button>
                <!-- The composed WhatsApp message the sales team pastes into
                     the prospect's chat. Disabled until the reservation date
                     is set — the message has a "reservada até X" sentence
                     that only reads right with an X. -->
                <button
                  type="button"
                  class="px-3 py-1.5 rounded bg-slate-100 text-slate-700 text-xs disabled:opacity-40 disabled:cursor-not-allowed"
                  :disabled="!canCopyMessage"
                  :title="
                    canCopyMessage
                      ? ''
                      : 'Reserve a proposta para gerar a mensagem.'
                  "
                  @click="copyMessage"
                >
                  {{ messageCopied ? 'Copiada!' : 'Copiar mensagem' }}
                </button>
              </div>
              <p class="text-xs text-slate-400 mt-2">
                Envie o link, o código e peça os 4 últimos dígitos do WhatsApp
                do cliente para ele abrir.
              </p>
            </div>
          </div>
        </div>

        <button
          type="button"
          class="mt-5 px-3 py-1.5 rounded bg-slate-100 text-slate-700 text-sm"
          @click="startOver"
        >
          Montar outra
        </button>
      </div>

      <div v-else class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 flex flex-col gap-6">
          <div class="border border-slate-100 rounded-lg p-5">
            <h2 class="text-sm font-medium text-slate-800 mb-3">1. Cliente</h2>

            <div class="relative" @focusout="onProspectPickerFocusOut">
              <input
                v-model="prospectTerm"
                type="text"
                autocomplete="off"
                placeholder="Buscar por nome, e-mail ou telefone…"
                class="w-full border border-slate-200 rounded px-3 py-2 text-sm focus:border-woot-500 focus:outline-none"
                @input="searchProspects"
              />

              <div
                v-if="prospectResults.length"
                class="absolute left-0 right-0 top-full mt-1 z-10 max-h-96 overflow-y-auto bg-white border border-slate-200 rounded-lg shadow-lg"
              >
                <ul class="py-1">
                  <li
                    v-for="prospect in prospectResults"
                    :key="prospect.task_id"
                  >
                    <button
                      type="button"
                      class="w-full px-3 py-2 text-left text-sm !text-slate-700 !bg-transparent hover:!bg-slate-100 hover:!text-slate-900"
                      @click="selectProspect(prospect)"
                    >
                      <div class="truncate">
                        {{ formatProspectRow(prospect) }}
                      </div>
                    </button>
                  </li>
                </ul>
              </div>
            </div>

            <p v-if="searching" class="text-xs text-slate-500 mt-2">
              Buscando…
            </p>

            <div v-if="selectedProspect" class="text-sm text-slate-700 mt-3">
              <span class="text-slate-500">Selecionado:</span>
              <strong>{{ formatProspectRow(selectedProspect) }}</strong>
              <span class="text-xs text-slate-400 ml-1">
                ({{ selectedProspect.task_id }})
              </span>
            </div>
          </div>

          <div class="border border-slate-100 rounded-lg p-5">
            <h2 class="text-sm font-medium text-slate-800 mb-3">
              2. Planos e adicionais
            </h2>
            <p v-if="loading" class="text-sm text-slate-500">Carregando…</p>

            <div
              v-else-if="productList.length"
              class="relative"
              @focusout="onProductPickerFocusOut"
            >
              <input
                v-model="productSearch"
                type="search"
                autocomplete="off"
                placeholder="Encontre ou adicione um produto…"
                class="w-full border border-slate-200 rounded px-3 py-2 text-sm focus:border-woot-500 focus:outline-none"
                @focus="openProductDropdown"
                @input="openProductDropdown"
              />

              <div
                v-if="productDropdownOpen"
                class="absolute left-0 right-0 top-full mt-1 z-10 max-h-96 overflow-y-auto bg-white border border-slate-200 rounded-lg shadow-lg"
              >
                <p
                  v-if="!filteredProducts.length"
                  class="px-3 py-2 text-sm text-slate-500"
                >
                  Nenhum produto para "{{ productSearch }}".
                </p>

                <ul v-else class="py-1">
                  <li
                    v-for="product in filteredProducts"
                    :key="product.id"
                    class="px-3 py-2"
                  >
                    <div class="text-sm font-medium text-slate-800">
                      {{ product.name }}
                    </div>
                    <p
                      v-if="product.description"
                      class="text-xs text-slate-500 mt-0.5 line-clamp-2"
                    >
                      {{ product.description }}
                    </p>

                    <ul class="mt-1">
                      <li v-for="price in product.prices" :key="price.id">
                        <button
                          type="button"
                          class="w-full flex items-center justify-between gap-3 px-2 py-1.5 rounded text-left text-sm !text-slate-700 !bg-transparent hover:!bg-slate-100 hover:!text-slate-900"
                          @click="selectPrice(price)"
                        >
                          <span>{{ priceAmountLabel(price) }}</span>
                          <span
                            v-if="price.usage_count"
                            class="text-xs text-slate-400 whitespace-nowrap"
                          >
                            {{ price.usage_count }}x vendido
                          </span>
                        </button>
                      </li>
                    </ul>
                  </li>
                </ul>
              </div>
            </div>

            <p v-else class="text-sm text-slate-500">
              Nenhum produto ativo no Stripe.
            </p>
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
                  = {{ formatAmount(cartItemLineTotal(item), item.currency) }}
                  <span v-if="item.tiered" class="ml-1 text-slate-400">
                    (por faixa)
                  </span>
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
                {{ couponLabel(coupon) }}
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
              class="flex justify-between text-green-700 mt-1"
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
