<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useToggle } from '@vueuse/core';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import WhatsAppCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import WhatsAppCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/WhatsAppCampaignEmptyState.vue';

const { t } = useI18n();
const getters = useStoreGetters();
const router = useRouter();
const route = useRoute();

const selectedCampaign = ref(null);
const [showWhatsAppCampaignDialog, toggleWhatsAppCampaignDialog] = useToggle();

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);

const WhatsAppCampaigns = computed(
  () => getters['campaigns/getWhatsAppCampaigns'].value
);

// Most recent first, a page at a time (the list is already loaded whole).
const PER_PAGE = 10;
const currentPage = ref(1);
const sortedCampaigns = computed(() =>
  [...(WhatsAppCampaigns.value || [])].sort((a, b) => b.id - a.id)
);
const pagedCampaigns = computed(() =>
  sortedCampaigns.value.slice(
    (currentPage.value - 1) * PER_PAGE,
    currentPage.value * PER_PAGE
  )
);

const hasNoWhatsAppCampaigns = computed(
  () => WhatsAppCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleReport = campaign => {
  router.push({
    name: 'campaigns_whatsapp_report',
    params: { ...route.params, campaignId: campaign.id },
  });
};

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.WHATSAPP.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.WHATSAPP.NEW_CAMPAIGN')"
    :close-on-click-outside="false"
    @click="toggleWhatsAppCampaignDialog()"
  >
    <template #action>
      <WhatsAppCampaignDialog
        v-if="showWhatsAppCampaignDialog"
        @close="toggleWhatsAppCampaignDialog(false)"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <div v-else-if="!hasNoWhatsAppCampaigns" class="flex flex-col gap-4">
      <CampaignList
        :campaigns="pagedCampaigns"
        @report="handleReport"
        @delete="handleDelete"
      />
      <PaginationFooter
        v-if="sortedCampaigns.length > PER_PAGE"
        :current-page="currentPage"
        :total-items="sortedCampaigns.length"
        :items-per-page="PER_PAGE"
        class="!px-0"
        @update:current-page="currentPage = $event"
      />
    </div>
    <WhatsAppCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.SUBTITLE')"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
