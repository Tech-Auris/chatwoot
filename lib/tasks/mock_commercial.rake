# Development-only mock data for the Commercial screens (Reservations,
# TermsAcceptances, PIX Renewals). Every row seeded here carries a
# `clickup_task_id` prefixed with MOCK_ so the task can wipe and re-seed
# on rerun without touching real proposals.
#
# Usage:
#   bundle exec rake commercial:mock_reservations
#
# The reservations page still calls ClickUp to refresh each row's status
# on load; the sync gracefully falls back to the stored value when
# ClickUp is not configured (see Sales::ReservationSyncService), so the
# seeded `clickup_status` sticks.
# rubocop:disable Metrics/BlockLength -- the seed table reads better inline
namespace :commercial do
  desc 'Seed a spread of SalesQuote rows covering every lifecycle status.'
  task mock_reservations: :environment do
    unless Rails.env.development?
      puts 'This task can only be run in the development environment.'
      exit(1)
    end

    seller = User.find_or_create_by!(email: 'mock-seller@auris.local') do |user|
      user.name = 'Vendedor Auris'
      # The User validator wants an uppercase letter and a special
      # character; a hex string alone is refused.
      user.password = "Mock!#{SecureRandom.hex(16)}A"
      user.confirmed_at = Time.current
    end

    require Rails.root.join('lib/dev/stub_prospects')

    # Each seed pairs a ClickUp stub prospect with the lifecycle stage
    # and the cart shape we want to see on the Reservations screen. The
    # prospect fields (name / clinic / phone / e-mail) come straight
    # from `Dev::StubProspects` so the row here and the autocomplete on
    # Montar plano show the same person, and so the last-4-digits gate
    # on the public proposal reads the same phone the seller sees.
    seeds = [
      { key: 'draft_empty', task_id: 'STUB_rafael_cardoso', status: :draft,
        details: false, reserved_until: nil, cart: :plan_monthly },
      { key: 'draft_confirmed', task_id: 'STUB_gustavo_teste', status: :details_confirmed,
        details: true, reserved_until: nil, cart: :plan_semiannual_with_addon },
      { key: 'reserved_empty', task_id: 'STUB_camila_vieira', status: :reserved,
        details: false, reserved_until: 3.days.from_now, cart: :plan_monthly },
      { key: 'reserved_confirmed', task_id: 'STUB_beatriz_prado', status: :details_confirmed,
        details: true, reserved_until: 5.days.from_now, cart: :plan_annual_with_addon },
      { key: 'signed', task_id: 'STUB_marcos_aurelio', status: :signed,
        details: true, reserved_until: 2.days.from_now, cart: :plan_annual, payment_method: :pix },
      { key: 'paid', task_id: 'STUB_isabela_nunes', status: :paid,
        details: true, reserved_until: 4.days.from_now, cart: :plan_semiannual_with_addon, payment_method: :card },
      { key: 'converted', task_id: 'STUB_lucas_almeida', status: :converted,
        details: true, reserved_until: 6.days.from_now, cart: :plan_monthly, payment_method: :card },
      { key: 'expired', task_id: 'STUB_fernanda_costa', status: :expired,
        details: false, reserved_until: 2.days.ago, cart: :plan_monthly }
    ]

    SalesQuote.where('clickup_task_id LIKE ?', 'MOCK_%').destroy_all

    seeds.each_with_index do |seed, index|
      prospect = Dev::StubProspects.find(seed[:task_id]) or
        raise "prospect #{seed[:task_id]} not found in Dev::StubProspects"

      quote = SalesQuote.new(
        seller: seller,
        clickup_task_id: "MOCK_#{seed[:key]}",
        clickup_status: prospect[:status],
        clickup_status_synced_at: Time.current,
        prospect_name: prospect[:name],
        # A prospect who has not filled the public form yet has no clinic
        # on the ClickUp task; fall back to a readable placeholder built
        # from their name, so the Reservations screen has a Cliente cell
        # to render.
        company_name: prospect[:clinic_name].presence || "Clínica de #{prospect[:name]}",
        billing_cycle: billing_cycle_for(seed[:cart]),
        payment_method: seed[:payment_method],
        reserved_until: seed[:reserved_until],
        status: seed[:status]
      )

      if seed[:details]
        quote.assign_attributes(
          prospect_email: prospect[:email].presence ||
                          "#{prospect[:name].parameterize}@mock.local",
          prospect_phone: prospect[:phone],
          # CPF is not on the ClickUp task, so we still synthesise it
          # deterministically off the seed index; only the shape matters
          # for the form validation.
          prospect_document: format('%<n>011d', n: (index + 1) * 1_234_567)
        )
      end

      items = build_items(seed[:cart])
      quote.items = items
      quote.subtotal_amount = items.sum { |item| item.unit_amount * item.quantity }
      quote.discount_amount = 0
      quote.total_amount = quote.subtotal_amount

      quote.save!
      quote.events.create!(event: 'mock_seed', user: seller, metadata: { key: seed[:key] })
    end

    puts "Seeded #{seeds.size} mock SalesQuote rows. Open /super_admin/commercial/reservations to see them."
  end

  desc 'Remove every SalesQuote row seeded by commercial:mock_reservations.'
  task clear_mock_reservations: :environment do
    unless Rails.env.development?
      puts 'This task can only be run in the development environment.'
      exit(1)
    end

    removed = SalesQuote.where('clickup_task_id LIKE ?', 'MOCK_%').destroy_all.size
    puts "Removed #{removed} mock SalesQuote rows."
  end

  def self.billing_cycle_for(cart)
    case cart
    when :plan_monthly, :plan_monthly_with_addon then :monthly
    when :plan_semiannual, :plan_semiannual_with_addon then :semiannual
    when :plan_annual, :plan_annual_with_addon then :annual
    end
  end

  # Realistic-ish carts so the "Valor" column reads something meaningful.
  # rubocop:disable Metrics/MethodLength -- the case/switch reads best inline
  def self.build_items(cart)
    plan = case cart
           when :plan_monthly, :plan_monthly_with_addon
             SalesQuoteItem.new(stripe_price_id: 'price_mock_monthly',
                                stripe_product_id: 'prod_mock_platform',
                                name: 'Plataforma Auris', unit_amount: 129_700, quantity: 1,
                                recurring_interval: 'month', kind: :plan)
           when :plan_semiannual, :plan_semiannual_with_addon
             SalesQuoteItem.new(stripe_price_id: 'price_mock_semiannual',
                                stripe_product_id: 'prod_mock_platform',
                                name: 'Plataforma Auris', unit_amount: 598_200, quantity: 1,
                                recurring_interval: 'month', kind: :plan)
           when :plan_annual, :plan_annual_with_addon
             SalesQuoteItem.new(stripe_price_id: 'price_mock_annual',
                                stripe_product_id: 'prod_mock_platform',
                                name: 'Plataforma Auris', unit_amount: 1_076_400, quantity: 1,
                                recurring_interval: 'year', kind: :plan)
           end

    return [plan] unless cart.to_s.include?('with_addon')

    addon = SalesQuoteItem.new(stripe_price_id: 'price_mock_channel',
                               stripe_product_id: 'prod_mock_channel',
                               name: 'Adicional de Canal', unit_amount: 6900, quantity: 2,
                               recurring_interval: 'month', kind: :addon)
    [plan, addon]
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/BlockLength
