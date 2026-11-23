import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import AgendaIndex from './agenda/Index.vue';

// The ERP menu. The Agenda opens for any account whose ERP or calendar has an
// agenda source (`agenda_enabled`), even without the ERP itself.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/erp/agenda'),
      name: 'erp_agenda',
      component: AgendaIndex,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
      beforeEnter: (to, from, next) => {
        const accountId = Number(to.params.accountId);
        const account = store.getters['accounts/getAccount'](accountId);
        if (account?.agenda_enabled !== true) {
          next({ name: 'home', params: { accountId } });
          return;
        }
        next();
      },
    },
  ],
};
