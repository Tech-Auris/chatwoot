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

// What the proposal is worth to us, as opposed to where ClickUp says the deal
// is. Only a converted proposal is a customer.
const STATUS_LABELS = {
  draft: 'Rascunho',
  reserved: 'Aguarda reserva',
  details_confirmed: 'Reservada',
  signed: 'Termos assinados',
  paid: 'Paga',
  converted: 'Conta criada',
  expired: 'Expirada',
  cancelled: 'Cancelada',
};

const reservations = ref([]);
const statuses = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
// The screen opens showing every proposal; the status and the free-text
// query narrow it down.
const statusFilter = ref('');
const queryFilter = ref('');
// Ganho and perdido are terminal: the deal is closed either way. Hidden by
// default so the screen shows what the team is still working on; a toggle
// brings them back when the seller wants the full history.
const showFinalized = ref(false);
// An expired reservation is a deal whose deadline already passed without
// a signature. Hidden by default for the same reason as the finalized ones
// — the screen opens on what is still moving.
const showExpired = ref(false);
const page = ref(1);
let queryDebounce = null;
const loading = ref(false);
const error = ref(null);
// Which row was copied and what was taken from it, so the feedback lands on the
// button that was actually pressed.
const copied = ref({ id: null, field: null });
const busyId = ref(null);
// Rows the operator opened by clicking on them — the sub-row shows the cart
// lines exactly like the proposal reads them.
const expandedIds = ref(new Set());
const isExpanded = reservation => expandedIds.value.has(reservation.id);
const toggleExpanded = (reservation, event) => {
  // Clicks that started on a button or a link stay with those controls;
  // only clicks on the row body itself toggle the sub-row.
  if (event?.target?.closest('button, a, input')) return;
  const next = new Set(expandedIds.value);
  if (next.has(reservation.id)) next.delete(reservation.id);
  else next.add(reservation.id);
  expandedIds.value = next;
};
const itemPeriodLabel = item =>
  item.recurring_interval ? 'recorrente' : 'avulso';

const fetchData = async () => {
  loading.value = true;
  error.value = null;
  try {
    const params = new URLSearchParams({ page: page.value });
    if (statusFilter.value) params.set('clickup_status', statusFilter.value);
    if (queryFilter.value.trim()) params.set('q', queryFilter.value.trim());
    if (showFinalized.value) params.set('include_finalized', '1');
    if (showExpired.value) params.set('include_expired', '1');

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
watch([statusFilter, showFinalized, showExpired], () => {
  page.value = 1;
  fetchData();
});

// Debounced so the fetch does not fire on every keystroke while the seller
// is still typing the term.
watch(queryFilter, () => {
  if (queryDebounce) clearTimeout(queryDebounce);
  queryDebounce = setTimeout(() => {
    page.value = 1;
    fetchData();
  }, 250);
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

// "Perdido" is a ClickUp-side terminal state — the proposal itself doesn't
// carry a `lost` status, so we read it off `clickup_status`. Green scale
// reads as progress toward "ganho": lighter tone for details_confirmed
// (reserved), darker for paid, darkest for the terminal won. Everything
// else stays neutral so the operator's eye lands on the ones moving.
const isLost = reservation =>
  reservation.clickup_status?.toLowerCase() === 'perdido';
const situationClass = reservation => {
  if (isLost(reservation)) return 'bg-red-50 text-red-700';
  if (reservation.won) return 'bg-green-200 text-green-900';
  if (reservation.status === 'paid') return 'bg-green-100 text-green-800';
  if (reservation.status === 'details_confirmed')
    return 'bg-green-50 text-green-600';
  return 'bg-slate-25 text-slate-600';
};
const situationLabel = reservation => {
  if (isLost(reservation)) return 'Perdido';
  if (reservation.won) return 'Ganho';
  return statusLabel(reservation.status);
};

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

// A sale that is `signed` and never had its money confirmed on the webhook
// needs somebody to click here. AsaaS card/boleto: one click, no modal.
// PIX: modal first so the operator picks whether the money came in through
// Inter (default) or AsaaS — the two places PIX can land.
const pixModal = ref({ open: false, reservation: null });

// Defined before the wrappers below to satisfy no-use-before-define.
const registerPayment = async (reservation, extraBody) => {
  busyId.value = reservation.id;
  error.value = null;
  try {
    const res = await fetch(
      `${props.componentData.reservations_url}/${reservation.id}/register_payment`,
      {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token':
            document.querySelector('meta[name="csrf-token"]')?.content ?? '',
        },
        body: JSON.stringify(extraBody || {}),
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

const openRegisterPayment = reservation => {
  if (reservation.payment_method === 'pix') {
    pixModal.value = { open: true, reservation };
    return;
  }

  const label = reservation.register_payment_label || 'pagamento';
  if (
    !window.confirm(
      `Registrar ${label} de ${reservation.prospect_name}? Isso cria a conta e a fatura no Stripe.`
    )
  )
    return;

  registerPayment(reservation, {});
};

const confirmPixRegister = paidVia => {
  const reservation = pixModal.value.reservation;
  pixModal.value = { open: false, reservation: null };
  if (reservation) registerPayment(reservation, { paid_via: paidVia });
};

const cancelPixRegister = () => {
  pixModal.value = { open: false, reservation: null };
};

// Boleto ships off por default em toda proposta nova — o vendedor
// libera aqui, mesmo padrão de "Dispensar cartão". Após liberado, o
// cliente passa a ver a opção de boleto na página pública.
const enableBoleto = async reservation => {
  if (
    !window.confirm('Liberar boleto como forma de pagamento para este cliente?')
  )
    return;

  busyId.value = reservation.id;
  error.value = null;
  try {
    const res = await fetch(
      `${props.componentData.reservations_url}/${reservation.id}/enable_boleto`,
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

// The expanded row shows the payment-link section only when at least one
// provider (AsaaS / Stripe / Inter) has produced something. Filtering
// here so the block collapses to zero markup on the common case.
const hasPaymentLinks = reservation =>
  Boolean(
    reservation.payment_links &&
      Object.values(reservation.payment_links).some(Boolean)
  );

// Rendering order + labels for each provider slot the sale might have
// produced. Kept next to the filter so a new provider is one entry away.
// `isTxid` on Inter tells the template to skip the anchor (Inter has no
// public cob URL, only the txid the finance team looks up).
const PAYMENT_LINK_ROWS = [
  { key: 'asaas_payment_link', label: 'AsaaS · Link' },
  { key: 'asaas_invoice', label: 'AsaaS · Fatura' },
  { key: 'stripe_dashboard', label: 'Stripe · Fatura' },
  { key: 'inter_pix_txid', label: 'Inter · PIX txid', isTxid: true },
];

const paymentLinkRows = reservation =>
  PAYMENT_LINK_ROWS.map(row => ({
    ...row,
    value: reservation.payment_links?.[row.key],
  })).filter(row => row.value);

// Lightweight clipboard for the payment-link buttons — no toast so the
// row stays quiet; the operator sees the URL selected in the address bar
// when they paste.
const copyLink = value => {
  if (!value) return;
  navigator.clipboard?.writeText(value);
};

// Reuses the shared builder so the wording is the same as the Quotes
// screen; disabled when no reservation date is set — the message has
// a "reservada até X" sentence that only reads right with an X.
const reservationMessage = reservation => buildReservationMessage(reservation);
const canCopyMessage = reservation =>
  isReservationMessageAvailable(reservation);

// "Vencida" here means the deadline passed AND the deal has not been won yet
// — a won deal is closed either way, no renewal to offer.
const isExpired = reservation =>
  !reservation.won &&
  reservation.reserved_until &&
  !reservation.reservation_active;

const tomorrowIso = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
};

const renewTarget = ref(null);
const renewDate = ref(tomorrowIso());
const renewing = ref(false);

const openRenew = reservation => {
  renewTarget.value = reservation;
  renewDate.value = tomorrowIso();
  error.value = null;
};

const closeRenew = () => {
  renewTarget.value = null;
};

const submitRenew = async () => {
  if (!renewTarget.value || !renewDate.value) return;

  renewing.value = true;
  error.value = null;
  try {
    const res = await fetch(
      `${props.componentData.quotes_url}/${renewTarget.value.id}/reserve`,
      {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token':
            document.querySelector('meta[name="csrf-token"]')?.content ?? '',
        },
        body: JSON.stringify({ reserved_until: renewDate.value }),
      }
    );
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    closeRenew();
    await fetchData();
  } catch (e) {
    error.value = e.message;
  } finally {
    renewing.value = false;
  }
};
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

    <div class="flex flex-wrap items-center gap-3 mb-4">
      <input
        v-model="queryFilter"
        type="text"
        placeholder="Buscar por nome, clínica, e-mail ou telefone…"
        class="text-sm border border-slate-200 rounded px-3 py-1.5 w-96 focus:border-woot-500 focus:outline-none"
      />
      <label class="text-sm text-slate-500">Status no ClickUp</label>
      <select
        v-model="statusFilter"
        class="text-sm border border-slate-200 rounded px-2 py-1 w-44"
      >
        <option value="">Todos</option>
        <option v-for="status in statuses" :key="status" :value="status">
          {{ status }}
        </option>
      </select>
      <label class="text-sm text-slate-600 flex items-center gap-1.5">
        <input v-model="showFinalized" type="checkbox" />
        Mostrar finalizadas
      </label>
      <label class="text-sm text-slate-600 flex items-center gap-1.5">
        <input v-model="showExpired" type="checkbox" />
        Mostrar vencidas
      </label>
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
          <th class="py-2 whitespace-nowrap">Status Ck</th>
          <th class="py-2">Situação</th>
          <th class="py-2 text-right whitespace-nowrap">Valor</th>
          <th class="py-2 text-right">Reserva até</th>
          <th class="py-2">Tokens</th>
          <th class="py-2">Envio ao cliente</th>
        </tr>
      </thead>
      <tbody>
        <template v-for="reservation in reservations" :key="reservation.id">
          <tr
            class="border-b border-slate-50 cursor-pointer hover:bg-slate-50"
            @click="toggleExpanded(reservation, $event)"
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

            <td class="py-3 whitespace-nowrap">
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
                :class="situationClass(reservation)"
              >
                {{ situationLabel(reservation) }}
              </span>
              <!-- A sale that never had its money confirmed on the webhook
                 (PIX, AsaaS card or AsaaS boleto) needs somebody to click
                 here. One click creates the Stripe customer + invoice and
                 the AurisChat account. PIX opens a small modal first to
                 pick where the transfer came in. The wrapping <div> keeps
                 the button on its own line under the situation pill; the
                 `reset-base` opts out of the admin's default filled-blue
                 button styling so the inline utility classes take. -->
              <div
                v-if="reservation.awaiting_manual_payment_confirmation"
                class="mt-1"
              >
                <button
                  type="button"
                  class="reset-base px-2 py-1 rounded border border-green-200 text-green-700 text-xs leading-tight whitespace-nowrap bg-white hover:bg-green-50 disabled:opacity-40"
                  :disabled="busyId === reservation.id"
                  title="Confirma o pagamento, cria o cliente e a fatura no Stripe, e converte a proposta em conta."
                  @click="openRegisterPayment(reservation)"
                >
                  Registrar pagamento · {{ reservation.register_payment_label }}
                </button>
              </div>
              <!-- Boleto liberação pré-venda — só aparece quando o plano
                   suporta boleto (semestral/anual), a reserva ainda vale
                   e o vendedor ainda não liberou. Após liberar, o cliente
                   passa a ver a opção na página pública. Some sozinho
                   quando a venda entra em "awaiting confirmation" (aí o
                   botão de Registrar pagamento acima já toma o espaço). -->
              <div
                v-if="
                  reservation.boleto_eligible_for_plan &&
                  reservation.reservation_active &&
                  !reservation.awaiting_manual_payment_confirmation
                "
                class="mt-1"
              >
                <span
                  v-if="reservation.boleto_enabled"
                  class="text-xs text-slate-500"
                >
                  Boleto liberado
                </span>
                <button
                  v-else
                  type="button"
                  class="reset-base px-2 py-1 rounded border border-woot-200 text-woot-600 text-xs leading-tight whitespace-nowrap bg-white hover:bg-woot-50 disabled:opacity-40"
                  :disabled="busyId === reservation.id"
                  title="Libera boleto como forma de pagamento para este cliente na página pública."
                  @click="enableBoleto(reservation)"
                >
                  Liberar boleto
                </button>
              </div>
            </td>

            <td class="py-3 text-right text-slate-700 whitespace-nowrap">
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
                class="reset-base px-2 py-1 rounded border border-woot-200 text-woot-600 text-xs leading-tight whitespace-nowrap bg-white hover:bg-woot-50 disabled:opacity-40"
                :disabled="busyId === reservation.id"
                title="Para quem pagou por PIX e não tem cartão. O consumo passa a ser cobrado por fatura."
                @click="waiveTokenCard(reservation)"
              >
                Dispensar cartão
              </button>
            </td>

            <td class="py-3">
              <div class="flex gap-1.5">
                <!-- Same composed WhatsApp message the Quotes screen offers,
                   so a seller who needs to re-send the reservation link
                   pastes exactly the copy the team agreed on. Disabled
                   when there is no `reserved_until` yet — the message
                   has a "até X" sentence that only reads right with an X. -->
                <button
                  type="button"
                  class="reset-base px-2 py-1 rounded border border-woot-200 text-woot-600 text-xs leading-tight whitespace-nowrap bg-white hover:bg-woot-50 disabled:opacity-40 disabled:cursor-not-allowed"
                  :disabled="!canCopyMessage(reservation)"
                  :title="
                    canCopyMessage(reservation)
                      ? ''
                      : 'Reserve a proposta para gerar a mensagem.'
                  "
                  @click="
                    copy(
                      reservation,
                      'message',
                      reservationMessage(reservation)
                    )
                  "
                >
                  {{
                    wasCopied(reservation, 'message') ? 'Copiada!' : 'Mensagem'
                  }}
                </button>
                <button
                  type="button"
                  class="reset-base px-2 py-1 rounded border border-woot-200 text-woot-600 text-xs leading-tight whitespace-nowrap bg-white hover:bg-woot-50"
                  @click="copy(reservation, 'link', reservation.public_url)"
                >
                  {{ wasCopied(reservation, 'link') ? 'Copiado!' : 'Link' }}
                </button>
                <button
                  type="button"
                  class="reset-base px-2 py-1 rounded border border-woot-200 text-woot-600 text-xs leading-tight whitespace-nowrap bg-white hover:bg-woot-50"
                  :title="`Código de acesso: ${reservation.access_code}`"
                  @click="copy(reservation, 'code', reservation.access_code)"
                >
                  {{
                    wasCopied(reservation, 'code')
                      ? 'Copiado!'
                      : reservation.access_code
                  }}
                </button>
                <!-- Only appears on a past-deadline reservation. Opens a modal
                   with a new deadline; posts to the same reserve endpoint
                   the wizard uses (Sales::ReserveQuoteService handles both
                   first-reserve and renewal). -->
                <button
                  v-if="isExpired(reservation)"
                  type="button"
                  class="reset-base px-2 py-1 rounded border border-woot-200 text-woot-600 text-xs leading-tight whitespace-nowrap bg-white hover:bg-woot-50"
                  @click="openRenew(reservation)"
                >
                  Renovar
                </button>
              </div>
            </td>
          </tr>

          <tr
            v-if="isExpanded(reservation)"
            class="bg-slate-50 border-b border-slate-100"
          >
            <td colspan="8" class="px-4 py-3">
              <div
                class="text-[10px] uppercase tracking-wide text-slate-500 mb-2"
              >
                Itens contratados
              </div>
              <ul v-if="reservation.items?.length" class="space-y-1 text-sm">
                <li
                  v-for="item in reservation.items"
                  :key="item.id"
                  class="flex justify-between text-slate-700"
                >
                  <span>
                    {{ item.name }}
                    <span v-if="item.quantity > 1" class="text-slate-400">
                      × {{ item.quantity }}
                    </span>
                    <span class="text-slate-400 ml-1">
                      ({{ itemPeriodLabel(item) }})
                    </span>
                  </span>
                  <span class="text-slate-700 whitespace-nowrap ml-4">
                    {{ formatAmount(item.total_amount) }}
                  </span>
                </li>
              </ul>
              <p v-else class="text-xs text-slate-400">
                Nenhum item na proposta.
              </p>
              <div
                class="mt-3 pt-2 border-t border-slate-200 text-xs flex justify-between text-slate-500"
              >
                <span>Subtotal</span>
                <span class="whitespace-nowrap">
                  {{ formatAmount(reservation.subtotal_amount) }}
                </span>
              </div>
              <div
                v-if="reservation.discount_amount > 0"
                class="mt-1 text-xs flex justify-between text-green-700"
              >
                <span>
                  Desconto{{
                    reservation.discount_summary
                      ? ` (${reservation.discount_summary})`
                      : ''
                  }}
                </span>
                <span class="whitespace-nowrap ml-4">
                  − {{ formatAmount(reservation.discount_amount) }}
                </span>
              </div>
              <div
                class="mt-1 text-sm font-medium flex justify-between text-slate-900"
              >
                <span>Total</span>
                <span class="whitespace-nowrap">
                  {{ formatAmount(reservation.total_amount) }}
                </span>
              </div>

              <div
                v-if="hasPaymentLinks(reservation)"
                class="mt-4 pt-3 border-t border-slate-200"
              >
                <div
                  class="text-[10px] uppercase tracking-wide text-slate-500 mb-2"
                >
                  Links de pagamento
                </div>
                <ul class="space-y-1 text-xs">
                  <li
                    v-for="row in paymentLinkRows(reservation)"
                    :key="row.key"
                    class="flex items-center gap-2"
                  >
                    <span class="text-slate-500 w-32">{{ row.label }}</span>
                    <a
                      v-if="!row.isTxid"
                      :href="row.value"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-woot-500 underline truncate max-w-md"
                    >
                      {{ row.value }}
                    </a>
                    <span
                      v-else
                      class="text-slate-700 font-mono truncate max-w-md"
                    >
                      {{ row.value }}
                    </span>
                    <button
                      type="button"
                      class="reset-base bg-transparent border-0 p-0 text-woot-500 hover:text-woot-700"
                      title="Copiar"
                      @click.stop="copyLink(row.value)"
                    >
                      <svg
                        width="14"
                        height="14"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true"
                      >
                        <rect
                          x="9"
                          y="9"
                          width="13"
                          height="13"
                          rx="2"
                          ry="2"
                        />
                        <path
                          d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"
                        />
                      </svg>
                    </button>
                  </li>
                </ul>
              </div>
            </td>
          </tr>
        </template>

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
        class="reset-base px-2 py-1 rounded border border-slate-200 text-slate-600 bg-white hover:bg-slate-50 disabled:opacity-40"
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
        class="reset-base px-2 py-1 rounded border border-slate-200 text-slate-600 bg-white hover:bg-slate-50 disabled:opacity-40"
        :disabled="page >= meta.total_pages"
        @click="page += 1"
      >
        Próxima
      </button>
    </div>

    <!-- Renew modal: the reserve endpoint (Sales::ReserveQuoteService) handles
         both first-reserve and re-reserve, so all this needs is a new date. -->
    <div
      v-if="renewTarget"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4"
      @click.self="closeRenew"
    >
      <div class="bg-white rounded shadow-lg w-full max-w-sm p-5">
        <h2 class="text-base font-medium text-slate-900">
          Renovar reserva de {{ renewTarget.prospect_name }}
        </h2>
        <p class="text-sm text-slate-500 mt-1">
          Informe a nova data de vencimento da reserva.
        </p>

        <label class="block mt-4 text-sm text-slate-600">
          Reservar até
          <input
            v-model="renewDate"
            type="date"
            class="mt-1 block w-full text-sm border border-slate-200 rounded px-2 py-1.5 focus:border-woot-500 focus:outline-none"
            :min="tomorrowIso()"
          />
        </label>

        <div class="flex justify-end gap-2 mt-5">
          <button
            type="button"
            class="reset-base px-3 py-1.5 text-sm rounded border border-slate-200 text-slate-600 bg-white hover:bg-slate-50"
            :disabled="renewing"
            @click="closeRenew"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-sm rounded bg-woot-500 text-white disabled:opacity-40"
            :disabled="renewing || !renewDate"
            @click="submitRenew"
          >
            {{ renewing ? 'Renovando…' : 'Renovar' }}
          </button>
        </div>
      </div>
    </div>

    <div
      v-if="pixModal.open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      @click.self="cancelPixRegister"
    >
      <div class="bg-white rounded-lg shadow-lg w-80 p-5">
        <h3 class="text-base font-medium text-slate-900 mb-1">
          Registrar pagamento PIX
        </h3>
        <p class="text-sm text-slate-600 mb-4">Onde o dinheiro caiu?</p>
        <div class="flex flex-col gap-2">
          <button
            type="button"
            class="w-full px-3 py-2 text-sm rounded bg-woot-500 text-white hover:bg-woot-600"
            @click="confirmPixRegister('inter')"
          >
            Banco Inter
          </button>
          <button
            type="button"
            class="reset-base justify-center w-full px-3 py-2 text-sm rounded border border-slate-200 text-slate-700 bg-white hover:bg-slate-50"
            @click="confirmPixRegister('asaas')"
          >
            AsaaS
          </button>
          <button
            type="button"
            class="reset-base justify-center w-full px-3 py-2 text-xs bg-transparent text-slate-500 hover:text-slate-700"
            @click="cancelPixRegister"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
