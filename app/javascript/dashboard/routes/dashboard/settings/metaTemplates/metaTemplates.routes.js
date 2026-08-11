import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import New from './New.vue';
import Edit from './Edit.vue';

// Read routes are open to every non-portal role (agent + manager +
// administrator); the sidebar link is gated on the account having at
// least one Cloud WhatsApp inbox (see Sidebar.vue). The create page is
// restricted to manager and administrator to match the backend
// MetaTemplatePolicy — agents that navigate directly land back on the
// index via the router guard.
const READ_PERMISSIONS = ['administrator', 'agent', 'manager', 'custom_role'];
const WRITE_PERMISSIONS = ['administrator', 'manager', 'custom_role'];

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/meta-templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'meta_templates_index',
          meta: {
            permissions: READ_PERMISSIONS,
          },
          component: Index,
        },
        {
          path: 'new',
          name: 'meta_templates_new',
          meta: {
            permissions: WRITE_PERMISSIONS,
          },
          component: New,
        },
        {
          path: ':id/edit',
          name: 'meta_templates_edit',
          meta: {
            permissions: WRITE_PERMISSIONS,
          },
          component: Edit,
        },
      ],
    },
  ],
};
