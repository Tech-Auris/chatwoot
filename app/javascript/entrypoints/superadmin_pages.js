import 'chart.js';
import { createApp, h } from 'vue';
import VueDOMPurifyHTML from 'vue-dompurify-html';

import PlaygroundIndex from '../superadmin_pages/views/playground/Index.vue';
import DashboardIndex from '../superadmin_pages/views/dashboard/Index.vue';
import InboxStatusIndex from '../superadmin_pages/views/reports/InboxStatus.vue';
import HealthScoreIndex from '../superadmin_pages/views/reports/HealthScore.vue';
import FinancialProductsIndex from '../superadmin_pages/views/financial/Products.vue';
import FinancialCustomerLinksIndex from '../superadmin_pages/views/financial/CustomerLinks.vue';
import FinancialSubscriptionsIndex from '../superadmin_pages/views/financial/Subscriptions.vue';
import FinancialInvoicesIndex from '../superadmin_pages/views/financial/Invoices.vue';
import FinancialTokenBillingsIndex from '../superadmin_pages/views/financial/TokenBillings.vue';

const ComponentMapping = {
  PlaygroundIndex: PlaygroundIndex,
  DashboardIndex: DashboardIndex,
  InboxStatusIndex: InboxStatusIndex,
  HealthScoreIndex: HealthScoreIndex,
  FinancialProductsIndex: FinancialProductsIndex,
  FinancialCustomerLinksIndex: FinancialCustomerLinksIndex,
  FinancialSubscriptionsIndex: FinancialSubscriptionsIndex,
  FinancialInvoicesIndex: FinancialInvoicesIndex,
  FinancialTokenBillingsIndex: FinancialTokenBillingsIndex,
};

const renderComponent = (componentName, props) => {
  const app = createApp({
    data() {
      return { props: props };
    },
    render() {
      return h(ComponentMapping[componentName], { componentData: this.props });
    },
  });

  app.use(VueDOMPurifyHTML);
  app.mount('#app');
};

document.addEventListener('DOMContentLoaded', () => {
  const element = document.getElementById('app');
  if (element) {
    const componentName = element.dataset.componentName;
    const props = JSON.parse(element.dataset.props);
    renderComponent(componentName, props);
  }
});
