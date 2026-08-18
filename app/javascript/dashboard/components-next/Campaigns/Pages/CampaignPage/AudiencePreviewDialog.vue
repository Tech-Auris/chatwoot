<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CampaignsAPI from 'dashboard/api/campaigns';

const props = defineProps({
  labelIds: {
    type: Array,
    default: () => [],
  },
  contactIds: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

const dialogRef = ref(null);
const contacts = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const isLoading = ref(false);
const error = ref('');

const withoutPhoneCount = computed(() => meta.value.without_phone_count ?? 0);

const fetchPage = async (page = 1) => {
  isLoading.value = true;
  error.value = '';
  try {
    const { data } = await CampaignsAPI.audiencePreview({
      labelIds: props.labelIds,
      contactIds: props.contactIds,
      page,
    });
    contacts.value = data.contacts ?? [];
    meta.value = data.meta ?? meta.value;
  } catch {
    error.value = t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.ERROR');
  } finally {
    isLoading.value = false;
  }
};

const open = () => {
  dialogRef.value.open();
  fetchPage(1);
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="
      t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.CLOSE')
    "
    width="2xl"
    overflow-y-auto
  >
    <div class="flex flex-col gap-3">
      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
      <p v-else-if="isLoading" class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.LOADING') }}
      </p>

      <template v-else>
        <p class="text-sm text-n-slate-11">
          {{
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.SUMMARY', {
              count: meta.total_count,
            })
          }}
          <span v-if="withoutPhoneCount" class="text-n-amber-11">
            {{
              t(
                'CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.WITHOUT_PHONE',
                {
                  count: withoutPhoneCount,
                }
              )
            }}
          </span>
        </p>

        <table class="w-full text-sm">
          <thead>
            <tr
              class="text-left text-xs uppercase text-n-slate-11 border-b border-n-weak"
            >
              <th class="py-2">
                {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.NAME') }}
              </th>
              <th class="py-2">
                {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.PHONE') }}
              </th>
              <th class="py-2">
                {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.EMAIL') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="contact in contacts"
              :key="contact.id"
              class="border-b border-n-weak/50"
              :class="contact.will_receive ? '' : 'text-n-slate-10'"
            >
              <td class="py-2">{{ contact.name }}</td>
              <td class="py-2">
                <span v-if="contact.will_receive">
                  {{ contact.phone_number }}
                </span>
                <span v-else class="text-n-amber-11">
                  {{
                    t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.NO_PHONE')
                  }}
                </span>
              </td>
              <td class="py-2">{{ contact.email }}</td>
            </tr>
          </tbody>
        </table>

        <div
          v-if="meta.total_pages > 1"
          class="flex items-center gap-3 text-sm"
        >
          <button
            type="button"
            class="text-n-blue-text disabled:opacity-40"
            :disabled="meta.current_page <= 1"
            @click="fetchPage(meta.current_page - 1)"
          >
            {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.PREVIOUS') }}
          </button>
          <span class="text-n-slate-11">
            {{
              t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.PAGE', {
                current: meta.current_page,
                total: meta.total_pages,
              })
            }}
          </span>
          <button
            type="button"
            class="text-n-blue-text disabled:opacity-40"
            :disabled="meta.current_page >= meta.total_pages"
            @click="fetchPage(meta.current_page + 1)"
          >
            {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_PREVIEW.NEXT') }}
          </button>
        </div>
      </template>
    </div>
  </Dialog>
</template>
