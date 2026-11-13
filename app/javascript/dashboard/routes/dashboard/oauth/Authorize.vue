<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import OAuthAuthorizationAPI from 'dashboard/api/oauthAuthorization';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const route = useRoute();

const isLoading = ref(true);
const isSubmitting = ref(false);
const clientName = ref('');
const accounts = ref([]);
const error = ref('');

const request = computed(() => route.query);
const canAuthorize = computed(() => accounts.value.length > 0);

onMounted(async () => {
  try {
    const { data } = await OAuthAuthorizationAPI.show(request.value);
    clientName.value = data.client_name;
    accounts.value = data.accounts;
  } catch (e) {
    error.value = e.response?.data?.error || 'invalid_request';
  } finally {
    isLoading.value = false;
  }
});

const respond = async approve => {
  isSubmitting.value = true;
  try {
    const { data } = await OAuthAuthorizationAPI.create({
      ...request.value,
      approve,
    });
    window.location.assign(data.redirect_url);
  } catch (e) {
    error.value = e.response?.data?.error || 'invalid_request';
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div
    class="flex items-center justify-center w-full min-h-screen px-4 bg-n-slate-2"
  >
    <div
      class="flex flex-col w-full max-w-md gap-5 p-6 rounded-xl bg-n-card outline outline-1 outline-n-container"
    >
      <Spinner v-if="isLoading" class="mx-auto" />

      <template v-else-if="error">
        <h1 class="text-heading-2 text-n-slate-12">
          {{ $t('OAUTH_AUTHORIZE.ERROR_TITLE') }}
        </h1>
        <p class="text-body-main text-n-slate-11">{{ error }}</p>
      </template>

      <template v-else>
        <h1 class="text-heading-2 text-n-slate-12">
          {{ $t('OAUTH_AUTHORIZE.TITLE', { client: clientName }) }}
        </h1>

        <template v-if="canAuthorize">
          <p class="text-body-main text-n-slate-11">
            {{ $t('OAUTH_AUTHORIZE.DESCRIPTION', { client: clientName }) }}
          </p>
          <ul class="list-disc ps-5 text-body-main text-n-slate-12">
            <li v-for="account in accounts" :key="account.id">
              {{ account.name }}
            </li>
          </ul>
          <p class="text-body-main text-n-slate-11">
            {{ $t('OAUTH_AUTHORIZE.READ_ONLY') }}
          </p>
        </template>
        <p v-else class="text-body-main text-n-slate-11">
          {{ $t('OAUTH_AUTHORIZE.NO_ACCOUNTS') }}
        </p>

        <div class="flex justify-end gap-2">
          <Button
            :label="$t('OAUTH_AUTHORIZE.DENY')"
            variant="faded"
            color="slate"
            :disabled="isSubmitting"
            @click="respond(false)"
          />
          <Button
            v-if="canAuthorize"
            :label="$t('OAUTH_AUTHORIZE.APPROVE')"
            :is-loading="isSubmitting"
            @click="respond(true)"
          />
        </div>
      </template>
    </div>
  </div>
</template>
