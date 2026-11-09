import store from 'dashboard/store';
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
      beforeEnter: (to, from, next) => {
        const accountId = Number(to.params.accountId);
        const account = store.getters['accounts/getAccount'](accountId);
        if (account?.id && account.home_enabled !== true) {
          next({ name: 'home', params: { accountId } });
          return;
        }
        next();
      },
    },
  ],
};
