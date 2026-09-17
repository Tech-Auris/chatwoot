<script setup>
import { useI18n } from 'vue-i18n';

// Per-ad table sitting below the funnel chart. Each row is one Meta ad
// (grouped by the Cloud referral's `source_id`), with the same funnel buckets
// the KPI strip above uses so a value in the grid always reconciles with the
// aggregate. The bucket "Em qualificação" is the first funnel stage past the
// entry point — the other three follow the KPI columns 1:1.
defineProps({
  rows: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

// Restrict the ad link to http(s) so a rogue webhook (unlikely, since these
// come from Meta, but this table also renders anything an operator seeded
// through additional_attributes) can't sneak a javascript: URL into href.
const toHttpUrl = url => {
  if (!url) return null;
  try {
    return ['http:', 'https:'].includes(new URL(url).protocol) ? url : null;
  } catch {
    return null;
  }
};

const formatRate = value => {
  if (value === null || value === undefined) return '--';
  return `${Number(value).toFixed(1)}%`;
};

const currencyFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const formatMoney = cents => {
  if (cents === null || cents === undefined) return '--';
  return currencyFormatter.format(cents / 100);
};

const formatRoas = roas =>
  roas === null || roas === undefined ? '--' : `${Number(roas).toFixed(2)}×`;
</script>

<template>
  <div>
    <div v-if="!rows.length" class="py-10 text-center text-n-slate-11 text-sm">
      {{ t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.EMPTY_STATE') }}
    </div>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-sm text-n-slate-12">
        <thead>
          <tr
            class="text-left text-xs font-medium text-n-slate-11 border-b border-n-weak"
          >
            <th class="py-2 pr-3 whitespace-nowrap">
              {{
                t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.AD_ID')
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap">
              {{
                t(
                  'FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.AD_TITLE'
                )
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.LEADS')
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t(
                  'FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.QUALIFYING'
                )
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t(
                  'FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.SCHEDULING'
                )
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t(
                  'FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.CONFIRMATION'
                )
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t(
                  'FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.ATTENDANCE'
                )
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.SPEND')
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.CPL')
              }}
            </th>
            <th class="py-2 pr-3 whitespace-nowrap text-right">
              {{
                t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.CPA')
              }}
            </th>
            <th class="py-2 pr-0 whitespace-nowrap text-right">
              {{
                t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.HEADERS.ROAS')
              }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.sourceId"
            class="border-b border-n-weak/50 last:border-b-0"
          >
            <td
              class="py-3 pr-3 whitespace-nowrap font-mono text-xs text-n-slate-11"
            >
              {{ row.sourceId }}
            </td>
            <td class="py-3 pr-3">
              <a
                v-if="toHttpUrl(row.sourceUrl)"
                :href="toHttpUrl(row.sourceUrl)"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-blue-9 hover:underline"
              >
                {{
                  row.title ||
                  t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.UNTITLED_AD')
                }}
              </a>
              <span v-else>
                {{
                  row.title ||
                  t('FUNNEL_CONVERSION_REPORTS.CAMPAIGN_BREAKDOWN.UNTITLED_AD')
                }}
              </span>
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right font-medium">
              {{ row.leads }}
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right">
              <div class="font-medium leading-tight">
                {{ row.qualifying.count }}
              </div>
              <div class="text-xs text-n-slate-11 leading-tight">
                {{ formatRate(row.qualifying.rate) }}
              </div>
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right">
              <div class="font-medium leading-tight">
                {{ row.scheduling.count }}
              </div>
              <div class="text-xs text-n-slate-11 leading-tight">
                {{ formatRate(row.scheduling.rate) }}
              </div>
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right">
              <div class="font-medium leading-tight">
                {{ row.confirmation.count }}
              </div>
              <div class="text-xs text-n-slate-11 leading-tight">
                {{ formatRate(row.confirmation.rate) }}
              </div>
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right">
              <div class="font-medium leading-tight">
                {{ row.attendance.count }}
              </div>
              <div class="text-xs text-n-slate-11 leading-tight">
                {{ formatRate(row.attendance.rate) }}
              </div>
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right font-medium">
              {{ formatMoney(row.spendCents) }}
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right">
              {{ formatMoney(row.cplCents) }}
            </td>
            <td class="py-3 pr-3 whitespace-nowrap text-right">
              {{ formatMoney(row.cpaCents) }}
            </td>
            <td class="py-3 pr-0 whitespace-nowrap text-right font-medium">
              {{ formatRoas(row.roas) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
