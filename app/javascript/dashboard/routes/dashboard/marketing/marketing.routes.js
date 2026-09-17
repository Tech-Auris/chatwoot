import { frontendURL } from '../../../helper/URLHelper';
import AnalyticsIndex from './analytics/Index.vue';

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
  ],
};
