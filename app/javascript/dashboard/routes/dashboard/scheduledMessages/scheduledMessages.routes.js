import { frontendURL } from '../../../helper/URLHelper';
import ScheduledMessagesIndex from './Index.vue';

// The account-wide "Mensagens → Agendadas" panel. The per-conversation
// scheduled-message drawer stays where it is; this one gives the operator
// a single place to see who has something scheduled without opening every
// thread.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/messages/scheduled'),
      name: 'scheduled_messages_index',
      component: ScheduledMessagesIndex,
      meta: {
        permissions: ['administrator', 'manager', 'agent'],
      },
    },
  ],
};
