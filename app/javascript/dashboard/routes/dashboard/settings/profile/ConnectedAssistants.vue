<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import authAPI from 'dashboard/api/auth';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const assistants = ref([]);

onMounted(async () => {
  const { data } = await authAPI.getOAuthApplications();
  assistants.value = data;
});

const disconnect = async assistant => {
  try {
    await authAPI.revokeOAuthApplication(assistant.id);
    assistants.value = assistants.value.filter(a => a.id !== assistant.id);
    useAlert(
      t('PROFILE_SETTINGS.FORM.CONNECTED_ASSISTANTS_SECTION.REVOKE_SUCCESS')
    );
  } catch {
    useAlert(
      t('PROFILE_SETTINGS.FORM.CONNECTED_ASSISTANTS_SECTION.REVOKE_ERROR')
    );
  }
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <p v-if="!assistants.length" class="text-body-main text-n-slate-11">
      {{ $t('PROFILE_SETTINGS.FORM.CONNECTED_ASSISTANTS_SECTION.EMPTY') }}
    </p>
    <div
      v-for="assistant in assistants"
      :key="assistant.id"
      class="flex items-center justify-between gap-4 rounded-xl border border-n-slate-4 bg-n-background p-4"
    >
      <div class="flex items-start gap-3">
        <Icon
          icon="i-lucide-sparkles"
          class="size-5 mt-0.5 text-n-slate-10 flex-shrink-0"
        />
        <div class="flex flex-col gap-1">
          <span class="text-heading-3 text-n-slate-12">
            {{ assistant.name }}
          </span>
          <span class="text-body-b3 text-n-slate-10">
            {{
              $t('PROFILE_SETTINGS.FORM.CONNECTED_ASSISTANTS_SECTION.SINCE', {
                date: format(
                  fromUnixTime(assistant.connected_at),
                  'dd/MM/yyyy'
                ),
              })
            }}
          </span>
        </div>
      </div>
      <Button
        type="button"
        faded
        xs
        color="ruby"
        :label="$t('PROFILE_SETTINGS.FORM.CONNECTED_ASSISTANTS_SECTION.REVOKE')"
        @click="disconnect(assistant)"
      />
    </div>
  </div>
</template>
