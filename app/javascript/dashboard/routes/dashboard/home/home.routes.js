import { frontendURL } from 'dashboard/helper/URLHelper';
import HomeIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/home'),
      name: 'home_overview',
      component: HomeIndex,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
    },
  ],
};
