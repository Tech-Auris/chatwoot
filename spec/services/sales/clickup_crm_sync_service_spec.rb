require 'rails_helper'

RSpec.describe Sales::ClickupCrmSyncService do
  let(:client) { instance_double(Integrations::Clickup::Client) }
  let(:quote) do
    create(:sales_quote, prospect_name: 'Fábio Rocha', prospect_email: 'fabio@clinica.com',
                         billing_cycle: :annual, payment_method: :card, total_amount: 1_286_760,
                         discount_amount: 143_000, clickup_task_id: '86akkgh7b')
  end

  before do
    allow(client).to receive(:set_custom_field)
    allow(client).to receive(:update_task)
  end

  def sync
    described_class.new(quote: quote, client: client).sync_paid_fields!
  end

  describe '#sync_paid_fields!' do
    # `clickup_task_id` is validated on the model, so stub the value for the
    # one negative test — every real code path reaches here with a task id,
    # but the guard is what protects against a legacy row without one.
    it 'does not touch ClickUp when the quote has no task id' do
      allow(quote).to receive(:clickup_task_id).and_return(nil)

      described_class.new(quote: quote, client: client).sync_paid_fields!

      expect(client).not_to have_received(:set_custom_field)
    end

    it 'writes the plan dropdown as the option matching the billing cycle' do
      quote.update!(billing_cycle: :semiannual)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:plan], '17f325cd-2f70-487c-9fb7-cf3c9c643a4f')
    end

    it 'writes the closing date as an epoch in milliseconds' do
      freeze_time = Time.zone.parse('2026-09-17 12:00:00')
      travel_to(freeze_time) { sync }

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:closed_at], (freeze_time.to_f * 1000).to_i)
    end

    it 'writes PIX as-is on a PIX sale' do
      quote.update!(payment_method: :pix, billing_cycle: :annual)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:payment_method], 'PIX')
    end

    it 'writes the card label with the locked instalment count on a long plan' do
      quote.update!(payment_method: :card, billing_cycle: :semiannual)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:payment_method], 'Cartão 6x')
    end

    it 'writes the boleto label with the instalment count' do
      quote.update!(payment_method: :boleto, billing_cycle: :annual)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:payment_method], 'Boleto 12x')
    end

    it 'writes the card label without an N on the monthly plan' do
      quote.update!(payment_method: :card, billing_cycle: :monthly)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:payment_method], 'Cartão')
    end

    it 'writes the prospect name on the responsible field' do
      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:responsible_name], 'Fábio Rocha')
    end

    # Base channels/professionals/units come with the plan; the add-ons are
    # counted on top. Fields 5, 6, 7 in the CK checklist.
    describe 'the channel / professional / unit counts' do
      before do
        create(:sales_quote_item, sales_quote: quote, name: 'Adicional de Canal',
                                  unit_amount: 5_000, quantity: 3)
        create(:sales_quote_item, sales_quote: quote, name: 'Adicional de Profissional',
                                  unit_amount: 4_000, quantity: 2)
      end

      it 'counts the added channels on top of the plan base' do
        sync

        expect(client).to have_received(:set_custom_field)
          .with('86akkgh7b', described_class::FIELDS[:channel_count], 5) # 3 addons + 2 base
      end

      it 'counts the added professionals on top of the plan base' do
        sync

        expect(client).to have_received(:set_custom_field)
          .with('86akkgh7b', described_class::FIELDS[:professional_count], 3) # 2 addons + 1 base
      end

      it 'keeps the unit count at the base when no unit was added' do
        sync

        expect(client).to have_received(:set_custom_field)
          .with('86akkgh7b', described_class::FIELDS[:unit_count], 1) # 0 addons + 1 base
      end
    end

    it 'writes the custom development quantity from its Stripe product' do
      create(:sales_quote_item, sales_quote: quote, name: 'Desenvolvimento Personalizado',
                                unit_amount: 100_000, quantity: 2,
                                stripe_product_id: described_class::CUSTOM_DEV_PRODUCT_ID)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:custom_dev_count], 2)
    end

    it 'writes zero on the setup counts when no matching product is on the sale' do
      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:unit_setup_count], 0)
    end

    # Setup add-ons are a labels multi-select on CK; the body carries an
    # `add:` list with the option id for each present product.
    it 'writes the setup addons that the sale carried, keyed by Stripe product id' do
      create(:sales_quote_item, sales_quote: quote, name: 'Implantação Guiada',
                                unit_amount: 300_000, stripe_product_id: 'prod_VEfJKxVbBhF2Xl')
      create(:sales_quote_item, sales_quote: quote, name: 'Configuração de API Meta',
                                unit_amount: 50_000, stripe_product_id: 'prod_VEfKJbd6SmlzZL')

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:setup_addons],
              { add: array_including('e787ba96-e509-4766-b55b-b36295368ef1',
                                     '961dbc4a-ea0a-4f85-bab7-7b212e1568db') })
    end

    it 'writes the total paid and the subscription discount in reais' do
      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:total_paid], 12_867.60)
      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:subscription_discount], 1_430.00)
    end

    # Subscription value = recurring line total / cycle months. On an annual
    # plan paid up-front this reveals the monthly value the customer signed
    # for, which is what the CRM tracks as MRR.
    it 'writes the monthly recurring value even when the plan was paid up-front' do
      # annual plan: one recurring item priced R$ 897/mês × 12 months = R$ 10.764 total recurring.
      create(:sales_quote_item, sales_quote: quote, name: 'Plataforma Auris',
                                unit_amount: 89_700, quantity: 12, recurring_interval: 'month')

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:subscription_value], 897.00)
    end

    it 'writes the implementation value as the sum of non-recurring lines in reais' do
      create(:sales_quote_item, sales_quote: quote, name: 'Implantação',
                                unit_amount: 300_000, recurring_interval: nil)
      create(:sales_quote_item, sales_quote: quote, name: 'Configuração de API Meta',
                                unit_amount: 50_000, recurring_interval: nil)

      sync

      expect(client).to have_received(:set_custom_field)
        .with('86akkgh7b', described_class::FIELDS[:implementation_value], 3_500.00)
    end

    it 'records the sync on the proposal history for auditability' do
      sync

      expect(quote.reload.events.pluck(:event)).to include('clickup_crm_paid_fields_synced')
    end
  end

  describe '#mark_closed!' do
    it 'flips the task status to negócio fechado' do
      described_class.new(quote: quote, client: client).mark_closed!

      expect(client).to have_received(:update_task).with('86akkgh7b', status: 'negócio fechado')
    end

    it 'does not touch ClickUp when the quote has no task id' do
      allow(quote).to receive(:clickup_task_id).and_return(nil)

      described_class.new(quote: quote, client: client).mark_closed!

      expect(client).not_to have_received(:update_task)
    end

    it 'records the status flip on the proposal history for auditability' do
      described_class.new(quote: quote, client: client).mark_closed!

      expect(quote.reload.events.pluck(:event)).to include('clickup_crm_status_closed')
    end
  end
end
