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

    # Six lifecycle rows plus one terminal, all identifiable by the MOCK_
    # prefix so a rerun wipes just what this task made.
    seeds = [
      { key: 'draft_empty', status: :draft, clickup_status: 'novo lead',
        prospect: 'Rafael Cardoso', clinic: 'Clínica Cardoso', details: false,
        reserved_until: nil, cart: :plan_monthly },
      { key: 'draft_confirmed', status: :details_confirmed, clickup_status: 'em análise',
        prospect: 'Gustavo Teste', clinic: 'Clínica Teste', details: true,
        reserved_until: nil, cart: :plan_semiannual_with_addon },
      { key: 'reserved_empty', status: :reserved, clickup_status: 'proposta enviada',
        prospect: 'Camila Vieira', clinic: 'Clínica Vieira', details: false,
        reserved_until: 3.days.from_now, cart: :plan_monthly },
      { key: 'reserved_confirmed', status: :details_confirmed, clickup_status: 'em análise',
        prospect: 'Beatriz Prado', clinic: 'Clínica Prado', details: true,
        reserved_until: 5.days.from_now, cart: :plan_annual_with_addon },
      { key: 'signed', status: :signed, clickup_status: 'assinou',
        prospect: 'Marcos Aurélio', clinic: 'Clínica Aurélio', details: true,
        reserved_until: 2.days.from_now, cart: :plan_annual, payment_method: :pix },
      { key: 'paid', status: :paid, clickup_status: 'pago',
        prospect: 'Isabela Nunes', clinic: 'Clínica Nunes', details: true,
        reserved_until: 4.days.from_now, cart: :plan_semiannual_with_addon, payment_method: :card },
      { key: 'converted', status: :converted, clickup_status: 'ganho',
        prospect: 'Lucas Almeida', clinic: 'Clínica Almeida', details: true,
        reserved_until: 6.days.from_now, cart: :plan_monthly, payment_method: :card },
      { key: 'expired', status: :expired, clickup_status: 'perdido',
        prospect: 'Fernanda Costa', clinic: 'Clínica Costa', details: false,
        reserved_until: 2.days.ago, cart: :plan_monthly }
    ]

    SalesQuote.where('clickup_task_id LIKE ?', 'MOCK_%').destroy_all

    seeds.each_with_index do |seed, index|
      quote = SalesQuote.new(
        seller: seller,
        clickup_task_id: "MOCK_#{seed[:key]}",
        clickup_status: seed[:clickup_status],
        clickup_status_synced_at: Time.current,
        prospect_name: seed[:prospect],
        company_name: seed[:clinic],
        billing_cycle: billing_cycle_for(seed[:cart]),
        payment_method: seed[:payment_method],
        reserved_until: seed[:reserved_until],
        status: seed[:status]
      )

      if seed[:details]
        quote.assign_attributes(
          prospect_email: "#{seed[:prospect].parameterize}@#{seed[:clinic].parameterize}.com",
          prospect_phone: format('+5561%<a>04d%<b>04d', a: index, b: index * 3),
          prospect_document: format('%<n>011d', n: index * 1_234_567)
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
