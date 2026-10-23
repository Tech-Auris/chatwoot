import { frontendURL } from '../../../helper/URLHelper';
import AnalyticsIndex from './analytics/Index.vue';
import AudiencesIndex from './audiences/Index.vue';
import AudienceForm from './audiences/Form.vue';
import AudienceShow from './audiences/Show.vue';

// Públicos: every account user builds and browses them; downloading one and
// sending a campaign to it are limited inside the pages.
const audiencesMeta = { permissions: ['administrator', 'manager', 'agent'] };

// Marketing-report namespace. Split from Settings routes because the pages
// live under the top-level Marketing sidebar menu (F1 reorg) — they are
// operator-facing reports, not admin configuration. Pixel + Meta Templates
// stay on their original settings-scoped routes for now; the sidebar just
// links to them from the new Marketing menu.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/marketing/analytics'),
      name: 'marketing_analytics_index',
      component: AnalyticsIndex,
      meta: {
        permissions: ['administrator', 'manager'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/marketing/audiences'),
      name: 'marketing_audiences_index',
      component: AudiencesIndex,
      meta: audiencesMeta,
    },
    {
      path: frontendURL('accounts/:accountId/marketing/audiences/new'),
      name: 'marketing_audiences_new',
      component: AudienceForm,
      meta: audiencesMeta,
    },
    {
      path: frontendURL('accounts/:accountId/marketing/audiences/:audienceId'),
      name: 'marketing_audiences_show',
      component: AudienceShow,
      meta: audiencesMeta,
    },
    {
      path: frontendURL(
        'accounts/:accountId/marketing/audiences/:audienceId/edit'
      ),
      name: 'marketing_audiences_edit',
      component: AudienceForm,
      meta: audiencesMeta,
    },
  ],
};
