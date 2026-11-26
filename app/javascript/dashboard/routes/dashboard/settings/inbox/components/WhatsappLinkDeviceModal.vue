<script setup>
import { onMounted, computed, onUnmounted, ref, watchEffect } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  onClose: { type: Function, required: true },
  isSetup: { type: Boolean, required: false },
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const { isAdmin, isManager } = useAdmin();

const providerConnection = computed(() => props.inbox.provider_connection);
const connection = computed(() => providerConnection.value?.connection);
const qrDataUrl = computed(() => providerConnection.value?.qr_data_url);
const pairingCode = computed(() => providerConnection.value?.pairing_code);
const error = computed(() => providerConnection.value?.error);
// A send stall leaves `connection` reading 'open': setup() would only refresh presence on a
// socket the provider already considers live, so the way out is disconnecting and re-pairing.
const sendStall = computed(() => providerConnection.value?.send_stall);

// Which pairing the operator asked for, not which one the provider has answered with
// yet: the code takes a moment to arrive, and the screen has to say what it is waiting
// for. Reset whenever the pairing ends, so the next one starts on the QR again.
const pairingMode = ref('qr');
// Only QR Code (Baileys) inboxes pair by code, and only admins and managers see the
// code, since it links the clinic's WhatsApp account just like the QR.
const canPairWithCode = computed(
  () => props.inbox.provider === 'baileys' && (isAdmin.value || isManager.value)
);
// WhatsApp shows the code as two groups of four.
const formattedPairingCode = computed(() =>
  pairingCode.value?.replace(/^(.{4})(.{4})$/, '$1-$2')
);

// Alternative onboarding when WhatsApp's extra device-linking verification blocks
// the QR: install the browser extension and import an already-linked session.
const extensionUrl =
  'https://chromewebstore.google.com/detail/fazerai-whatsapp-connecto/nchdjpjplcnggifnemiiclgjplooible';

const loading = ref(false);
const showImportDetails = ref(false);

const handleError = e => {
  useAlert(e.message);
  loading.value = false;
};
const setup = () => {
  loading.value = true;
  pairingMode.value = 'qr';
  store
    .dispatch('inboxes/setupChannelProvider', props.inbox.id)
    .catch(handleError);
};
// Asking again is how a code that expired is replaced, so this stays reachable while one
// is already on screen.
const pairWithCode = () => {
  loading.value = true;
  pairingMode.value = 'code';
  store
    .dispatch('inboxes/requestPairingCode', props.inbox.id)
    .then(() => {
      // Already `connecting` while the QR was up, so the watcher below never fires;
      // the panel shows the wait for the code on its own.
      loading.value = false;
    })
    .catch(handleError);
};
const disconnect = () => {
  loading.value = true;
  store
    .dispatch('inboxes/disconnectChannelProvider', props.inbox.id)
    .catch(handleError);
};

onMounted(() => {
  if (!connection.value || connection.value === 'close') {
    setup();
  }
});
onUnmounted(() => {
  if (
    connection.value === 'connecting' ||
    connection.value === 'reconnecting'
  ) {
    disconnect();
  }
});
watchEffect(() => {
  if (connection.value) {
    loading.value = false;
  }
  if (connection.value && connection.value !== 'connecting') {
    pairingMode.value = 'qr';
  }
});
</script>

<template>
  <woot-modal :show="show" size="small" @close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.TITLE'
          )
        "
        :header-content="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.SUBTITLE'
          )
        "
      />

      <div class="flex flex-col gap-4 p-8 pt-4">
        <div class="flex flex-col gap-4 items-center">
          <InboxName
            :inbox="inbox"
            class="!text-lg"
            with-phone-number
            with-provider-connection-status
          />

          <template
            v-if="
              !connection ||
              connection === 'close' ||
              (error && connection !== 'open')
            "
          >
            <p v-if="error" class="text-red-500 text-center">
              {{ error }}
            </p>
            <Button :is-loading="loading" @click="setup">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LINK_DEVICE'
                )
              }}
            </Button>
          </template>

          <template v-else-if="connection === 'connecting'">
            <template v-if="pairingMode === 'code'">
              <div v-if="!pairingCode" class="flex flex-col gap-4 items-center">
                <p>
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LOADING_PAIRING_CODE'
                    )
                  }}
                </p>
                <Spinner />
              </div>
              <div v-else class="flex flex-col gap-2 items-center">
                <p
                  class="font-mono text-3xl font-semibold tracking-widest select-all text-n-slate-12"
                >
                  {{ formattedPairingCode }}
                </p>
                <p class="max-w-xs text-sm text-center text-n-slate-11">
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.PAIRING_CODE_HELP'
                    )
                  }}
                </p>
              </div>
            </template>

            <template v-else>
              <div v-if="!qrDataUrl" class="flex flex-col gap-4 items-center">
                <p>
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LOADING_QRCODE'
                    )
                  }}
                </p>
                <Spinner />
              </div>
              <img
                v-else
                :src="qrDataUrl"
                alt="QR Code"
                class="w-[276px] h-[276px]"
              />
            </template>

            <template v-if="canPairWithCode">
              <Button
                v-if="pairingMode === 'code'"
                link
                blue
                :is-loading="loading"
                :label="
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.USE_QRCODE'
                  )
                "
                @click="setup"
              />
              <Button
                v-else
                link
                blue
                :is-loading="loading"
                :label="
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.USE_PAIRING_CODE'
                  )
                "
                @click="pairWithCode"
              />
            </template>
          </template>

          <template v-else-if="connection === 'reconnecting'">
            <p>
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.RECONNECTING'
                )
              }}
            </p>
            <Spinner />
          </template>

          <template v-else-if="connection === 'open'">
            <p v-if="error" class="text-center text-red-500">
              {{ error }}
            </p>
            <p v-else-if="isSetup" class="text-center">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.CONNECTED'
                )
              }}
            </p>
            <div class="flex gap-2">
              <Button
                :variant="sendStall ? 'solid' : 'ghost'"
                :color="sendStall ? 'ruby' : 'blue'"
                :is-loading="loading"
                @click="disconnect"
              >
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.DISCONNECT'
                  )
                }}
              </Button>
              <router-link
                v-if="isSetup"
                :to="{
                  name: 'inbox_dashboard',
                  params: { inboxId: inbox.id },
                }"
              >
                <Button
                  solid
                  teal
                  :label="$t('INBOX_MGMT.FINISH.BUTTON_TEXT')"
                />
              </router-link>
            </div>
          </template>

          <!-- Fallback kept available in every non-open state, including while the
               QR is shown: import an already-linked session via the extension. -->
          <div
            v-if="connection !== 'open'"
            class="flex flex-col gap-1 items-center pt-4 mt-2 w-full border-t border-n-weak"
          >
            <p class="text-sm font-medium text-center text-n-slate-12">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_TITLE'
                )
              }}
            </p>
            <button
              v-if="!showImportDetails"
              type="button"
              :aria-expanded="showImportDetails"
              class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
              @click="showImportDetails = true"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_SHOW_MORE'
                )
              }}
            </button>
            <template v-else>
              <p class="text-sm text-center text-n-slate-11">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_DESC'
                  )
                }}
              </p>
              <a :href="extensionUrl" target="_blank" rel="noopener noreferrer">
                <Button
                  link
                  blue
                  :label="
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.IMPORT_SESSION_INSTALL'
                    )
                  "
                />
              </a>
            </template>
          </div>
        </div>
      </div>
    </div>
  </woot-modal>
</template>
