<script setup>
/* global axios */
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import VariableList from 'dashboard/components/widgets/conversation/VariableList.vue';
import WhatsappTemplatesModal from 'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

// A lean v1 of the composer that lets the operator schedule a message
// from the Agendadas panel without having to open a conversation first.
// Reuses the existing conversation-drawer modal for anything more
// elaborate (rich formatting, attachment, recurrence, WhatsApp
// templates). Two picker rows at the top mirror the "+ Nova mensagem"
// pencil flow so muscle memory carries over.

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:show', 'scheduled']);

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');

const store = useStore();
const contactQuery = ref('');
const contactResults = ref([]);
const contactSearchLoading = ref(false);
const selectedContact = ref(null);
const contactInboxes = ref([]);
const selectedInboxId = ref(null);
const message = ref('');
const scheduledAt = ref('');
const holdOnReply = ref(true);
const isSaving = ref(false);
// Template WhatsApp (Cloud oficial da Meta) — quando escolhido, o
// operador está agendando um envio de template. `content` recebe o
// texto renderizado (com variáveis preenchidas) só para preview; o
// payload verdadeiro é `templateParams`, que o job de disparo lê e
// passa pro MessageBuilder pra rotear via WhatsApp Cloud API.
const templateParams = ref(null);
const showTemplatePickerModal = ref(false);

// Textarea auto-grow — o composer de template do WhatsApp na Meta cresce
// junto com o texto, e o operador pediu o mesmo aqui pra caber mensagens
// mais longas sem obrigar o scroll interno.
const messageTextareaRef = ref(null);
const MIN_TEXTAREA_HEIGHT = 128;
const MAX_TEXTAREA_HEIGHT = 400;
const VARIABLE_TRIGGER = '{{';
const resizeTextarea = () => {
  const el = messageTextareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  const next = Math.min(
    Math.max(el.scrollHeight, MIN_TEXTAREA_HEIGHT),
    MAX_TEXTAREA_HEIGHT
  );
  el.style.height = `${next}px`;
};

// Variable picker — reaproveita o `VariableList` que o composer de
// conversas usa. Sensor simples: quando o usuário digita `{{` e continua
// dentro dele, mostra o dropdown; ao escolher, substitui o fragmento
// `{{search` por `{{ variable.key }}` e devolve o cursor pra depois.
const showVariablePicker = ref(false);
const variableSearchKey = ref('');
const variableStartPos = ref(0);

const evaluateVariablePicker = () => {
  const el = messageTextareaRef.value;
  if (!el) {
    showVariablePicker.value = false;
    return;
  }
  const caret = el.selectionStart ?? message.value.length;
  const before = message.value.slice(0, caret);
  const openIdx = before.lastIndexOf('{{');
  if (openIdx === -1) {
    showVariablePicker.value = false;
    return;
  }
  const fragment = before.slice(openIdx + 2);
  // Um `}` ou uma quebra de linha fecha o contexto — se aparecerem
  // depois do `{{` mais recente, não estamos mais dentro dele.
  if (/[}\n]/.test(fragment)) {
    showVariablePicker.value = false;
    return;
  }
  variableStartPos.value = openIdx;
  variableSearchKey.value = fragment;
  showVariablePicker.value = true;
};

const onMessageInput = () => {
  resizeTextarea();
  evaluateVariablePicker();
};

// Ao sair do textarea, fecha o picker — mas com atraso curto para o
// clique numa opção do MentionBox conseguir disparar antes do teardown.
let blurCloseHandle = null;
const onMessageBlur = () => {
  if (blurCloseHandle) clearTimeout(blurCloseHandle);
  blurCloseHandle = setTimeout(() => {
    showVariablePicker.value = false;
  }, 150);
};
const onMessageFocus = () => {
  if (blurCloseHandle) {
    clearTimeout(blurCloseHandle);
    blurCloseHandle = null;
  }
};

const insertVariable = variableKey => {
  const el = messageTextareaRef.value;
  if (!el) return;
  const caret = el.selectionStart ?? message.value.length;
  const before = message.value.slice(0, variableStartPos.value);
  const after = message.value.slice(caret);
  const replacement = `{{ ${variableKey} }}`;
  message.value = `${before}${replacement}${after}`;
  showVariablePicker.value = false;
  nextTick(() => {
    resizeTextarea();
    const nextCaret = before.length + replacement.length;
    el.focus();
    el.setSelectionRange(nextCaret, nextCaret);
  });
};

// Custom attributes populam variáveis extras (ex.: `contact.custom_attribute.
// birthday`), então garantimos que o store carregou antes de abrir a lista.
onMounted(() => {
  store.dispatch('attributes/get');
});

// Caixas do usuário logado — o Vuex já carrega só o que ele pode
// ver (administrator / manager: todas; agent: só as inboxes onde é
// membro). Usado pra filtrar o dropdown Via, evitando que o agente
// escolha uma caixa que o backend depois recusa com 403.
const myInboxes = useMapGetter('inboxes/getInboxes');
const accessibleInboxIds = computed(
  () => new Set((myInboxes.value || []).map(i => i.id))
);
const accessibleContactInboxes = computed(() =>
  (contactInboxes.value || []).filter(ci =>
    accessibleInboxIds.value.has(ci.inbox?.id)
  )
);

// Lista de inboxes que aparece no dropdown Via. Antes do contato ser
// escolhido, mostra todas as inboxes do usuário — o operador pode
// escolher primeiro por qual caixa quer enviar. Depois do contato, o
// filtro fecha nas inboxes onde ele realmente existe (pra não agendar
// pra uma inbox que o backend depois rejeita).
const inboxOptionsForVia = computed(() => {
  if (selectedContact.value) {
    return accessibleContactInboxes.value.map(ci => ci.inbox);
  }
  return myInboxes.value || [];
});

const selectedInbox = computed(() =>
  (myInboxes.value || []).find(i => i.id === selectedInboxId.value)
);

// WhatsApp Cloud API é qualquer inbox WhatsApp cujo provider não é
// baileys nem zapi (as duas alternativas não-oficiais). Fora da janela
// de 24h, essas inboxes só aceitam envio como template — enviar texto
// livre agendado dá erro. Enquanto o template picker não chega, exibe
// um aviso pro operador não se surpreender no dia do envio.
const isWhatsappCloudInbox = computed(() => {
  const inbox = selectedInbox.value;
  if (!inbox) return false;
  if (inbox.channel_type !== INBOX_TYPES.WHATSAPP) return false;
  const provider = inbox.provider || '';
  return provider !== 'baileys' && provider !== 'zapi';
});

// Labels compactos pro chip do "Para" e "Via", casando com o formato
// do lápis: `nome (email)`, `nome (telefone)` ou só `nome` quando não
// há nem uma coisa nem outra.
const selectedContactLabel = computed(() => {
  const c = selectedContact.value;
  if (!c) return '';
  const detail = c.email || c.phone_number;
  if (!detail) return c.name || '';
  return c.name ? `${c.name} (${detail})` : detail;
});

const selectedInboxLabel = computed(() => {
  const inbox = selectedInbox.value;
  if (!inbox) return '';
  const phone = inbox.phone_number;
  return phone ? `${inbox.name} (${phone})` : inbox.name;
});

const hasTemplate = computed(
  () => templateParams.value && Object.keys(templateParams.value).length > 0
);

const templateName = computed(
  () => templateParams.value?.name || templateParams.value?.id || null
);

const openTemplatePicker = () => {
  showTemplatePickerModal.value = true;
};

const closeTemplatePicker = () => {
  showTemplatePickerModal.value = false;
};

const onTemplatePicked = payload => {
  // O `WhatsappTemplates/Modal.vue` emite `{ message, templateParams }`
  // após o operador escolher o template e preencher as variáveis.
  templateParams.value = payload.templateParams || null;
  message.value = payload.message || '';
  closeTemplatePicker();
  nextTick(() => resizeTextarea());
};

const clearTemplate = () => {
  templateParams.value = null;
  message.value = '';
  nextTick(() => resizeTextarea());
};

// A fresh contact search fires whenever the operator types >= 2 chars.
// The endpoint is the same one the pencil flow calls; results carry
// `contact_inboxes` inline so we can populate Via without a follow-up.
let searchTimer = null;
watch(contactQuery, value => {
  const query = value.trim();
  if (query.length < 2) {
    contactResults.value = [];
    return;
  }
  clearTimeout(searchTimer);
  searchTimer = setTimeout(async () => {
    contactSearchLoading.value = true;
    try {
      const res = await axios.get(
        `/api/v1/accounts/${accountId.value}/contacts/search`,
        { params: { q: query, include: 'contact_inboxes' } }
      );
      contactResults.value = res.data?.payload || [];
    } catch (e) {
      contactResults.value = [];
    } finally {
      contactSearchLoading.value = false;
    }
  }, 300);
});

const pickContact = contact => {
  selectedContact.value = contact;
  contactQuery.value = contact.name || contact.phone_number || '';
  contactResults.value = [];
  contactInboxes.value = contact.contact_inboxes || [];
  const accessible = accessibleContactInboxes.value;
  // Preserva a inbox que o operador já escolheu (fluxo "Via primeiro,
  // contato depois") desde que o contato exista nessa mesma inbox.
  const stillValid =
    selectedInboxId.value &&
    accessible.some(ci => ci.inbox?.id === selectedInboxId.value);
  if (stillValid) return;
  selectedInboxId.value =
    accessible.length === 1 ? accessible[0].inbox?.id : null;
};

const clearContact = () => {
  selectedContact.value = null;
  contactInboxes.value = [];
  selectedInboxId.value = null;
  contactQuery.value = '';
};

// The three shortcuts mirror what the conversation-drawer modal shows so
// muscle memory holds. Amanhã de manhã = tomorrow 08:00, amanhã à tarde
// = tomorrow 13:00, segunda de manhã = next Monday 08:00. The local
// datetime input carries whatever the operator picked (either a
// shortcut just filled it in, or they typed).
const scheduleShortcuts = computed(() => {
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const morning = new Date(tomorrow);
  morning.setHours(8, 0, 0, 0);
  const afternoon = new Date(tomorrow);
  afternoon.setHours(13, 0, 0, 0);
  const monday = new Date(now);
  const dayShift = (8 - monday.getDay()) % 7 || 7;
  monday.setDate(monday.getDate() + dayShift);
  monday.setHours(8, 0, 0, 0);
  return [
    { id: 'tomorrow-morning', label: 'Amanhã de manhã', date: morning },
    { id: 'tomorrow-afternoon', label: 'Amanhã à tarde', date: afternoon },
    { id: 'monday-morning', label: 'Segunda-feira de manhã', date: monday },
  ].map(entry => ({
    ...entry,
    display: entry.date.toLocaleString('pt-BR', {
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
    }),
  }));
});

const applyShortcut = shortcut => {
  // The datetime-local input expects `YYYY-MM-DDTHH:mm` in local time.
  const pad = n => String(n).padStart(2, '0');
  const d = shortcut.date;
  scheduledAt.value =
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const canSubmit = computed(() => {
  if (!selectedContact.value) return false;
  if (!selectedInboxId.value) return false;
  if (!scheduledAt.value) return false;
  if (isSaving.value) return false;
  // Template picked → basta ter `templateParams` (content vem renderizado
  // do próprio parser). Sem template → o texto livre precisa existir.
  if (hasTemplate.value) return true;
  return message.value.trim().length > 0;
});

const close = () => emit('update:show', false);

const reset = () => {
  clearContact();
  message.value = '';
  scheduledAt.value = '';
  holdOnReply.value = true;
  showVariablePicker.value = false;
  templateParams.value = null;
  showTemplatePickerModal.value = false;
  nextTick(() => resizeTextarea());
};

const submit = async () => {
  if (!canSubmit.value) return;
  isSaving.value = true;
  try {
    // Convert the local `YYYY-MM-DDTHH:mm` back to an ISO the server can
    // read as UTC without inheriting the app's `Time.zone`.
    const iso = new Date(scheduledAt.value).toISOString();
    const payload = {
      contact_id: selectedContact.value.id,
      inbox_id: selectedInboxId.value,
      content: message.value,
      scheduled_at: iso,
      hold_on_reply: holdOnReply.value,
    };
    if (hasTemplate.value) payload.template_params = templateParams.value;
    await axios.post(
      `/api/v1/accounts/${accountId.value}/scheduled_messages`,
      payload
    );
    useAlert(t('SCHEDULED.NEW.DONE'));
    emit('scheduled');
    reset();
    close();
  } catch (e) {
    useAlert(
      e.response?.data?.errors?.join(', ') ||
        e.message ||
        t('SCHEDULED.NEW.FAILED')
    );
  } finally {
    isSaving.value = false;
  }
};

watch(
  () => props.show,
  value => {
    if (!value) reset();
  }
);

// Se o operador tinha uma inbox selecionada e trocou o contato (ou
// limpou), a inbox anterior pode não fazer mais parte das opções.
// Limpar pra não enviar um valor "fantasma" no submit.
watch(inboxOptionsForVia, options => {
  if (
    selectedInboxId.value &&
    !options.some(i => i.id === selectedInboxId.value)
  ) {
    selectedInboxId.value = null;
  }
});

// Trocar a inbox depois de já ter escolhido um template invalidaria a
// escolha (o template pertence à caixa anterior), então limpa. O
// operador reabre o picker com o template set da nova inbox.
watch(selectedInboxId, () => {
  if (hasTemplate.value) clearTemplate();
});
</script>

<template>
  <teleport to="body">
    <!-- Clicar fora do modal (na backdrop) NÃO fecha — o operador acaba
         de gastar minutos escolhendo contato, escrevendo a mensagem e
         montando o cronograma; um clique acidental fora perdia o trabalho
         inteiro. Fecha só pelos botões Cancelar (footer) ou X (header),
         ou depois que o Agendar salva com sucesso. -->
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 py-6"
    >
      <div
        class="w-full max-w-2xl bg-n-solid-1 rounded-xl shadow-xl flex flex-col max-h-[92vh] overflow-hidden"
      >
        <header class="flex items-start justify-between px-6 pt-5 pb-3">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('SCHEDULED.NEW.TITLE') }}
          </h2>
          <button
            type="button"
            class="!p-0 w-8 h-8 inline-flex items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :title="t('MEDIA_HUB.CLOSE')"
            @click="close"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </header>

        <div class="flex-1 overflow-y-auto px-6 pb-5 flex flex-col gap-4">
          <!-- Para: label inline + chip compacto quando o contato está
               escolhido, ou input de busca full-width com dropdown
               inferior quando ainda não. Mesmo shape que o lápis usa
               em `ContactSelector.vue` — reduz duas linhas verticais
               (rótulo em bloco + campo abaixo) pra uma só. -->
          <div class="relative">
            <div class="flex items-baseline gap-3 min-h-7">
              <label
                class="text-sm font-medium text-n-slate-11 whitespace-nowrap"
              >
                {{ t('SCHEDULED.NEW.CONTACT_LABEL') }}
              </label>
              <div
                v-if="selectedContact"
                class="flex items-center gap-1 rounded-md bg-n-alpha-2 pl-3 pr-1 h-7 min-w-0"
              >
                <span class="text-sm truncate text-n-slate-12">
                  {{ selectedContactLabel }}
                </span>
                <button
                  type="button"
                  class="!p-0 w-5 h-5 inline-flex items-center justify-center rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
                  :title="t('SCHEDULED.NEW.CLEAR_CONTACT')"
                  @click="clearContact"
                >
                  <span class="i-lucide-x size-3.5" />
                </button>
              </div>
              <input
                v-else
                v-model="contactQuery"
                type="text"
                autofocus
                :placeholder="t('SCHEDULED.NEW.CONTACT_PLACEHOLDER')"
                class="flex-1 min-w-0 border border-n-slate-3 rounded-md px-3 h-7 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
              />
            </div>
            <ul
              v-if="!selectedContact && contactResults.length"
              class="absolute z-10 mt-1 w-full max-h-56 overflow-y-auto rounded-md border border-n-slate-3 bg-n-solid-1 shadow-lg"
            >
              <li
                v-for="contact in contactResults"
                :key="contact.id"
                class="px-3 py-2 text-sm cursor-pointer hover:bg-n-slate-2"
                @click="pickContact(contact)"
              >
                <div class="text-n-slate-12">
                  {{ contact.name || t('SCHEDULED.NO_CONTACT_NAME') }}
                </div>
                <div class="text-xs text-n-slate-11">
                  {{ contact.phone_number || contact.email }}
                </div>
              </li>
            </ul>
            <p
              v-else-if="!selectedContact && contactSearchLoading"
              class="mt-1 text-xs text-n-slate-11"
            >
              {{ t('SCHEDULED.NEW.SEARCHING') }}
            </p>
          </div>

          <!-- Via: mesmo shape do Para. Chip compacto com nome + número
               quando a inbox está escolhida; select nativo (compacto,
               com chevron custom via PR anterior) quando ainda não.
               O aviso Cloud e o botão de template ficam abaixo, na
               própria linha, pra não engordar a row do Via. -->
          <div>
            <div class="flex items-baseline gap-3 min-h-7">
              <label
                class="text-sm font-medium text-n-slate-11 whitespace-nowrap"
              >
                {{ t('SCHEDULED.NEW.INBOX_LABEL') }}
              </label>
              <div
                v-if="selectedInbox"
                class="flex items-center gap-1 rounded-md bg-n-alpha-2 pl-3 pr-1 h-7 min-w-0"
              >
                <span class="text-sm truncate text-n-slate-12">
                  {{ selectedInboxLabel }}
                </span>
                <button
                  type="button"
                  class="!p-0 w-5 h-5 inline-flex items-center justify-center rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
                  @click="selectedInboxId = null"
                >
                  <span class="i-lucide-x size-3.5" />
                </button>
              </div>
              <!-- appearance-none + chevron custom absoluto — o CSS
                   global do `<select>` (em `_base.scss`) usa uma
                   `background-position` inválida que os navegadores
                   descartam, e o triângulo cai no top-left. -->
              <div
                v-else-if="inboxOptionsForVia.length"
                class="relative flex-1 min-w-0"
              >
                <select
                  v-model="selectedInboxId"
                  class="appearance-none !bg-none w-full border border-n-slate-3 rounded-md pl-3 pr-8 h-7 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
                >
                  <option :value="null" disabled>
                    {{ t('SCHEDULED.NEW.INBOX_PLACEHOLDER') }}
                  </option>
                  <option
                    v-for="inbox in inboxOptionsForVia"
                    :key="inbox.id"
                    :value="inbox.id"
                  >
                    {{ inbox.name }}
                  </option>
                </select>
                <span
                  class="i-lucide-chevron-down size-4 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-n-slate-11"
                />
              </div>
              <p v-else-if="selectedContact" class="text-xs text-n-amber-11">
                {{ t('SCHEDULED.NEW.INBOX_UNREACHABLE') }}
              </p>
            </div>
            <!-- WhatsApp Cloud (oficial da Meta): fora da janela de 24h
                 só aceita envio como template. Botão compacto abaixo
                 do Via ("Selecione o modelo") abre o TemplatesPicker;
                 depois de escolhido, vira badge com opção de trocar. -->
            <div
              v-if="isWhatsappCloudInbox && !hasTemplate"
              class="mt-2 flex items-center gap-2"
            >
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md border border-n-slate-3 text-n-slate-12 px-3 h-7 text-xs font-medium hover:bg-n-alpha-2"
                @click="openTemplatePicker"
              >
                <span
                  class="i-lucide-message-square size-3.5 text-n-slate-11"
                />
                {{ t('SCHEDULED.NEW.PICK_TEMPLATE') }}
              </button>
              <span class="text-xs text-n-amber-11">
                {{ t('SCHEDULED.NEW.WHATSAPP_CLOUD_TEMPLATE_NOTICE') }}
              </span>
            </div>
            <div
              v-else-if="hasTemplate"
              class="mt-2 flex items-center gap-1 rounded-md bg-n-alpha-2 pl-3 pr-1 h-7 w-fit max-w-full"
            >
              <span class="text-xs truncate text-n-slate-12">
                {{
                  t('SCHEDULED.NEW.TEMPLATE_SELECTED', { name: templateName })
                }}
              </span>
              <button
                type="button"
                class="!p-0 w-5 h-5 inline-flex items-center justify-center rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
                :title="t('SCHEDULED.NEW.CLEAR_TEMPLATE')"
                @click="clearTemplate"
              >
                <span class="i-lucide-x size-3.5" />
              </button>
            </div>
          </div>

          <!-- Message: textarea auto-grow + picker de variáveis (`{{`).
               A dica sobre `{{` fica sempre visível pra o operador
               descobrir a funcionalidade sem precisar receber onboarding
               separado. Quando um template do WhatsApp Cloud já foi
               escolhido, o campo vira preview readonly (o texto vem
               renderizado do parser com as variáveis preenchidas). -->
          <div class="relative">
            <div class="flex items-baseline justify-between gap-2">
              <label class="text-sm font-medium text-n-slate-12">
                {{
                  hasTemplate
                    ? t('SCHEDULED.NEW.TEMPLATE_PREVIEW_LABEL')
                    : t('SCHEDULED.NEW.MESSAGE_LABEL')
                }}
              </label>
              <span v-if="!hasTemplate" class="text-xs text-n-slate-11">
                {{ t('SCHEDULED.NEW.VARIABLE_HINT_PREFIX') }}
                <code class="text-n-slate-12">{{ VARIABLE_TRIGGER }}</code>
                {{ t('SCHEDULED.NEW.VARIABLE_HINT_SUFFIX') }}
              </span>
            </div>
            <textarea
              ref="messageTextareaRef"
              v-model="message"
              :placeholder="t('SCHEDULED.NEW.MESSAGE_PLACEHOLDER')"
              :readonly="hasTemplate"
              class="mt-1 w-full border border-n-slate-3 rounded-md px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none resize-none"
              :class="hasTemplate ? 'bg-n-alpha-2 cursor-not-allowed' : ''"
              :style="{ minHeight: `${MIN_TEXTAREA_HEIGHT}px` }"
              @input="onMessageInput"
              @keyup="evaluateVariablePicker"
              @click="evaluateVariablePicker"
              @focus="onMessageFocus"
              @blur="onMessageBlur"
            />
            <div
              v-if="showVariablePicker && !hasTemplate"
              class="absolute left-0 right-0 top-full mt-1 z-20"
            >
              <VariableList
                :search-key="variableSearchKey"
                @select-variable="insertVariable"
              />
            </div>
          </div>

          <!-- Schedule -->
          <div>
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('SCHEDULED.NEW.SCHEDULE_LABEL') }}
            </label>
            <div
              class="mt-1 flex flex-col gap-2 border border-n-slate-3 rounded-md bg-n-alpha-2 p-2"
            >
              <button
                v-for="shortcut in scheduleShortcuts"
                :key="shortcut.id"
                type="button"
                class="!p-0 w-full flex items-center justify-between px-3 py-2 text-sm rounded-md hover:bg-n-solid-1 text-n-slate-12"
                @click="applyShortcut(shortcut)"
              >
                <span>{{ shortcut.label }}</span>
                <span class="text-xs text-n-slate-11">{{
                  shortcut.display
                }}</span>
              </button>
              <div
                class="border-t border-n-slate-3 pt-2 flex items-center gap-2"
              >
                <span class="i-lucide-keyboard size-4 text-n-slate-11" />
                <input
                  v-model="scheduledAt"
                  type="datetime-local"
                  class="flex-1 bg-transparent text-sm text-n-slate-12 focus:outline-none"
                />
              </div>
            </div>
          </div>

          <!-- Hold on reply -->
          <label
            class="flex items-start gap-3 rounded-md border border-n-slate-3 bg-n-alpha-2 px-3 py-2"
          >
            <input
              v-model="holdOnReply"
              type="checkbox"
              class="mt-0.5 accent-woot-500"
            />
            <div>
              <div class="text-sm font-medium text-n-slate-12">
                {{ t('SCHEDULED.NEW.HOLD_ON_REPLY') }}
              </div>
              <div class="text-xs text-n-slate-11 mt-0.5">
                {{ t('SCHEDULED.NEW.HOLD_ON_REPLY_HINT') }}
              </div>
            </div>
          </label>
        </div>

        <footer
          class="border-t border-n-slate-4 px-6 py-3 flex justify-end gap-2"
        >
          <button
            type="button"
            class="px-4 py-2 rounded-md text-sm text-n-slate-12 hover:bg-n-alpha-2"
            @click="close"
          >
            {{ t('SCHEDULED.NEW.CANCEL') }}
          </button>
          <button
            type="button"
            class="px-4 py-2 rounded-md text-sm font-medium bg-woot-500 text-white disabled:opacity-40"
            :disabled="!canSubmit"
            @click="submit"
          >
            {{
              isSaving ? t('SCHEDULED.NEW.SAVING') : t('SCHEDULED.NEW.SUBMIT')
            }}
          </button>
        </footer>
      </div>
    </div>

    <!-- Modal do template do WhatsApp: recebe o inbox id, renderiza o
         `TemplatesPicker` + `WhatsAppTemplateParser`, emite o payload
         final quando o operador confirma. Fica dentro do `teleport` pra
         herdar o z-index acima da backdrop principal. -->
    <WhatsappTemplatesModal
      v-model:show="showTemplatePickerModal"
      :inbox-id="selectedInboxId"
      :send-button-label="t('SCHEDULED.NEW.PICK_TEMPLATE_CONFIRM')"
      @on-send="onTemplatePicked"
      @cancel="closeTemplatePicker"
    />
  </teleport>
</template>
