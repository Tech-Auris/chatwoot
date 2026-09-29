<script setup>
import { onMounted, ref, watch } from 'vue';

// Commercial → Settings: the account and inbox (the main seller's WhatsApp)
// the proposal messages to leads go out from, and the time of the last-day
// reminder. The inbox list follows the account picked.
const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const accounts = ref([]);
const inboxes = ref([]);
const accountId = ref(null);
const inboxId = ref(null);
const reminderTime = ref('12:30');
const loading = ref(true);
const saving = ref(false);
const error = ref(null);
const saved = ref(false);

const getJson = async url => {
  const res = await fetch(url, {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
  return body;
};

const loadInboxes = async id => {
  inboxes.value = id
    ? await getJson(`${props.componentData.inboxes_url}?account_id=${id}`)
    : [];
};

const save = async () => {
  saving.value = true;
  error.value = null;
  saved.value = false;
  try {
    const res = await fetch(props.componentData.settings_url, {
      method: 'PATCH',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token':
          document.querySelector('meta[name="csrf-token"]')?.content ?? '',
      },
      body: JSON.stringify({
        account_id: accountId.value,
        inbox_id: inboxId.value,
        reminder_time: reminderTime.value,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    saved.value = true;
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
};

onMounted(async () => {
  try {
    const [settings, accountList] = await Promise.all([
      getJson(props.componentData.settings_url),
      getJson(props.componentData.accounts_url),
    ]);
    accounts.value = accountList;
    accountId.value = settings.account_id;
    reminderTime.value = settings.reminder_time;
    await loadInboxes(settings.account_id);
    inboxId.value = settings.inbox_id;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
});

// Picking another account resets the inbox: it has to be one of that
// account's inboxes.
watch(accountId, async (next, previous) => {
  if (loading.value || previous === null) return;
  inboxId.value = null;
  saved.value = false;
  await loadInboxes(next);
});
</script>

<template>
  <div class="p-6 max-w-2xl">
    <h1 class="text-xl font-medium text-slate-900 mb-1">Settings</h1>
    <p class="text-sm text-slate-600 mb-6">
      Por onde as mensagens das propostas chegam aos leads no WhatsApp (o link
      da reserva ao reservar e o lembrete no último dia) e a que horas o
      lembrete é enviado.
    </p>

    <div v-if="loading" class="text-sm text-slate-600">Carregando…</div>

    <form
      v-else
      class="flex flex-col gap-5 bg-white rounded-lg border border-slate-100 p-6"
      @submit.prevent="save"
    >
      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-slate-800">Conta</span>
        <select
          v-model="accountId"
          class="reset-base rounded border border-slate-200 px-2 py-1.5"
        >
          <option
            v-for="account in accounts"
            :key="account.id"
            :value="account.id"
          >
            {{ account.id }} · {{ account.name }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-slate-800">Caixa de entrada</span>
        <select
          v-model="inboxId"
          class="reset-base rounded border border-slate-200 px-2 py-1.5"
          :disabled="!inboxes.length"
        >
          <option :value="null" disabled>Escolha a caixa</option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.id }} · {{ inbox.name }}
          </option>
        </select>
        <span class="text-xs text-slate-500">
          Caixa do vendedor principal. As mensagens saem por ela e o contato é
          criado nessa conta quando ainda não existe.
        </span>
      </label>

      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-slate-800">
          Horário do lembrete de último dia
        </span>
        <input
          v-model="reminderTime"
          type="time"
          class="reset-base rounded border border-slate-200 px-2 py-1.5 w-32"
        />
        <span class="text-xs text-slate-500">
          Horário de Brasília. No último dia da reserva, quem ainda não
          contratou recebe o lembrete a partir desse horário.
        </span>
      </label>

      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
      <p v-if="saved" class="text-sm text-green-700">Configurações salvas.</p>

      <div class="flex justify-end">
        <button
          type="submit"
          class="reset-base px-4 py-2 rounded bg-woot-500 text-white text-sm disabled:opacity-50"
          :disabled="saving || !accountId || !inboxId || !reminderTime"
        >
          {{ saving ? 'Salvando…' : 'Salvar' }}
        </button>
      </div>
    </form>
  </div>
</template>
