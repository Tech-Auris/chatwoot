<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const MCP_URL = 'https://mcp.auris.ia.br/mcp';

const store = useStore();
const { t } = useI18n();

const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const account = computed(() => getAccount.value(accountId.value));
const enabled = computed(() => !!account.value.mcp_enabled);

const termsDialog = ref(null);
const termsAccepted = ref(false);
const isSaving = ref(false);

const enabledInfo = computed(() => {
  if (!account.value.mcp_enabled_at) return '';
  return t('INTEGRATION_SETTINGS.MCP.ENABLED_INFO', {
    date: format(
      fromUnixTime(account.value.mcp_enabled_at),
      'dd/MM/yyyy HH:mm'
    ),
    name: account.value.mcp_enabled_by_name || '',
  });
});

const claudeCodeCommand = `claude mcp add --transport http auris ${MCP_URL} --header "Authorization: Bearer <token>"`;

const save = async data => {
  isSaving.value = true;
  try {
    await store.dispatch('accounts/updateMcp', data);
    useAlert(
      data.enabled
        ? t('INTEGRATION_SETTINGS.MCP.ENABLED_SUCCESS')
        : t('INTEGRATION_SETTINGS.MCP.DISABLED_SUCCESS')
    );
    return true;
  } catch {
    useAlert(t('INTEGRATION_SETTINGS.MCP.ERROR'));
    return false;
  } finally {
    isSaving.value = false;
  }
};

const onToggle = value => {
  if (value) {
    termsAccepted.value = false;
    termsDialog.value.open();
  } else {
    save({ enabled: false });
  }
};

const confirmTerms = async () => {
  const saved = await save({ enabled: true, terms_accepted: true });
  if (saved) termsDialog.value.close();
};

const copy = async text => {
  await copyTextToClipboard(text);
  useAlert(t('INTEGRATION_SETTINGS.MCP.COPIED'));
};
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.MCP.HEADER')"
        :description="$t('INTEGRATION_SETTINGS.MCP.DESCRIPTION')"
        feature-name="integrations"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-6 max-w-3xl">
        <div
          class="flex items-start justify-between gap-4 p-4 rounded-xl outline outline-1 outline-n-container bg-n-card"
        >
          <div class="flex flex-col gap-1">
            <span class="text-heading-3 text-n-slate-12">
              {{ $t('INTEGRATION_SETTINGS.MCP.SWITCH_LABEL') }}
            </span>
            <p class="text-body-main text-n-slate-11">
              {{ $t('INTEGRATION_SETTINGS.MCP.SWITCH_HELP') }}
            </p>
            <p v-if="enabled" class="text-body-main text-n-teal-11">
              {{ enabledInfo }}
            </p>
          </div>
          <Switch
            :model-value="enabled"
            :disabled="isSaving"
            @update:model-value="onToggle"
          />
        </div>

        <div v-if="enabled" class="flex flex-col gap-4">
          <h3 class="text-heading-3 text-n-slate-12">
            {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.TITLE') }}
          </h3>
          <div
            class="flex items-center justify-between gap-2 px-3 py-2 rounded-lg bg-n-alpha-2"
          >
            <code class="text-sm text-n-slate-12 break-all">{{ MCP_URL }}</code>
            <Button
              :label="$t('INTEGRATION_SETTINGS.MCP.COPY')"
              icon="i-lucide-copy"
              xs
              faded
              @click="copy(MCP_URL)"
            />
          </div>

          <div class="flex flex-col gap-1">
            <span class="font-medium text-n-slate-12">
              {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.CLAUDE.TITLE') }}
            </span>
            <ol class="list-decimal ps-5 text-body-main text-n-slate-11">
              <li>
                {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.CLAUDE.STEP_1') }}
              </li>
              <li>
                {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.CLAUDE.STEP_2') }}
              </li>
              <li>{{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.LOGIN_STEP') }}</li>
            </ol>
          </div>

          <div class="flex flex-col gap-1">
            <span class="font-medium text-n-slate-12">
              {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.CHATGPT.TITLE') }}
            </span>
            <ol class="list-decimal ps-5 text-body-main text-n-slate-11">
              <li>
                {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.CHATGPT.STEP_1') }}
              </li>
              <li>
                {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.CHATGPT.STEP_2') }}
              </li>
              <li>{{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.LOGIN_STEP') }}</li>
            </ol>
          </div>

          <details class="text-body-main text-n-slate-11">
            <summary class="cursor-pointer font-medium text-n-slate-12">
              {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.ADVANCED.TITLE') }}
            </summary>
            <div class="flex flex-col gap-2 mt-2">
              <p>{{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.ADVANCED.HELP') }}</p>
              <div
                class="flex items-center justify-between gap-2 px-3 py-2 rounded-lg bg-n-alpha-2"
              >
                <code class="text-sm text-n-slate-12 break-all">
                  {{ claudeCodeCommand }}
                </code>
                <Button
                  :label="$t('INTEGRATION_SETTINGS.MCP.COPY')"
                  icon="i-lucide-copy"
                  xs
                  faded
                  @click="copy(claudeCodeCommand)"
                />
              </div>
              <router-link
                :to="{ name: 'profile_settings_index' }"
                class="text-n-brand"
              >
                {{ $t('INTEGRATION_SETTINGS.MCP.CONNECT.ADVANCED.TOKEN_LINK') }}
              </router-link>
            </div>
          </details>
        </div>
      </div>

      <Dialog
        ref="termsDialog"
        :title="$t('INTEGRATION_SETTINGS.MCP.TERMS.TITLE')"
        :confirm-button-label="$t('INTEGRATION_SETTINGS.MCP.TERMS.CONFIRM')"
        :disable-confirm-button="!termsAccepted"
        :is-loading="isSaving"
        @confirm="confirmTerms"
      >
        <div class="flex flex-col gap-3 text-body-main text-n-slate-11">
          <p>{{ $t('INTEGRATION_SETTINGS.MCP.TERMS.PARAGRAPH_1') }}</p>
          <p>{{ $t('INTEGRATION_SETTINGS.MCP.TERMS.PARAGRAPH_2') }}</p>
          <p>{{ $t('INTEGRATION_SETTINGS.MCP.TERMS.PARAGRAPH_3') }}</p>
          <label class="flex items-center gap-2 text-n-slate-12 cursor-pointer">
            <Checkbox v-model="termsAccepted" />
            {{ $t('INTEGRATION_SETTINGS.MCP.TERMS.ACCEPT') }}
          </label>
        </div>
      </Dialog>
    </template>
  </SettingsLayout>
</template>
