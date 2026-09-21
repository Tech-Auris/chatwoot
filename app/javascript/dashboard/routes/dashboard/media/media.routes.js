import { frontendURL } from '../../../helper/URLHelper';
import MediaHub from './Index.vue';

// The Mídia hub lives at the top level of the sidebar (below Marketing),
// serving every attachment / link the account produced. Not scoped to a
// single conversation — the point is finding an old asset across threads.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/media'),
      name: 'media_hub_index',
      component: MediaHub,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
    },
  ],
};
