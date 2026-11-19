import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import VirtualClinicIndex from './Index.vue';

// Released per account from Super Admin → Auris menus. Any other value than
// `true` sends the user back home, like the sidebar hides the item.
const guardRelease = (to, from, next) => {
  const accountId = Number(to.params.accountId);
  const account = store.getters['accounts/getAccount'](accountId);
  if (account?.virtual_clinic_enabled !== true) {
    next({ name: 'home', params: { accountId } });
    return;
  }
  next();
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/virtual-clinic'),
      name: 'virtual_clinic_index',
      component: VirtualClinicIndex,
      meta: { permissions: ['administrator', 'manager', 'agent'] },
      beforeEnter: guardRelease,
    },
  ],
};
