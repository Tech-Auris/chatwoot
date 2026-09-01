# Dev-only stub for the Stripe catalogue behind the Commercial screens.
# When STRIPE_STUB=1 is set, Integrations::Stripe::Client answers a
# fixed catalogue of products, prices and coupons — enough to exercise
# the Montar plano picker without a valid STRIPE_SECRET_KEY.
#
# Never active in production. The catalogue mirrors the shape a real
# Stripe response has: `.data` on the list, Struct-like objects with
# attribute accessors, `recurring` nil for one-off prices and a nested
# `{interval, interval_count}` for subscriptions.
return unless Rails.env.development? && ENV['STRIPE_STUB'] == '1'

module SalesStripeStub
  # Attribute shapes match what `serialize_price` / `category_of` /
  # `billing_period_of` in the quotes controller read from the real
  # Stripe SDK. Keep the field lists in sync with those helpers.
  Product = Struct.new(:id, :name, :description, :active, :metadata, keyword_init: true)
  Price = Struct.new(:id, :product, :unit_amount, :currency, :recurring, :active, :nickname,
                     :billing_scheme, :tiers_mode, :tiers, keyword_init: true)
  Coupon = Struct.new(:id, :name, :percent_off, :amount_off, :currency, :valid, keyword_init: true)
  Recurring = Struct.new(:interval, :interval_count, keyword_init: true)
  Tier = Struct.new(:up_to, :unit_amount, :flat_amount, keyword_init: true)
  List = Struct.new(:data)

  # `interval_count` is what tells a monthly plan (1) from a semiannual
  # one (6); Stripe uses `month × 6` for the semester and either
  # `year × 1` or `month × 12` for the year.
  MONTHLY = Recurring.new(interval: 'month', interval_count: 1).freeze
  SEMIANNUAL = Recurring.new(interval: 'month', interval_count: 6).freeze
  ANNUAL = Recurring.new(interval: 'year', interval_count: 1).freeze

  def self.product(id, name, description, category: nil)
    metadata = category ? { 'auris_category' => category } : {}
    Product.new(id: id, name: name, description: description, active: true, metadata: metadata)
  end

  def self.price(id, product_id, cents, recurring: nil)
    Price.new(id: id, product: product_id, unit_amount: cents, currency: 'brl',
              recurring: recurring, active: true, nickname: nil,
              billing_scheme: 'per_unit', tiers_mode: nil, tiers: nil)
  end

  # Tiered price: `unit_amount` is nil on the top level, the amount lives
  # inside the tiers array. `graduated` charges each band separately;
  # `volume` charges the whole quantity at the tier the total lands in.
  def self.tiered_price(id, product_id, tiers, recurring: nil, mode: 'graduated')
    Price.new(id: id, product: product_id, unit_amount: nil, currency: 'brl',
              recurring: recurring, active: true, nickname: nil,
              billing_scheme: 'tiered', tiers_mode: mode,
              tiers: tiers.map { |band| Tier.new(**band) })
  end

  PRODUCTS = [
    product('prod_stub_platform', 'Plataforma Auris',
            'Plataforma completa: IA de atendimento, canais integrados e painel humano.'),
    product('prod_stub_channel', 'Adicional de Canal',
            'Um canal extra (WhatsApp, Instagram, e-mail…) conectado à sua conta.'),
    product('prod_stub_professional', 'Adicional de Profissional',
            'Um profissional a mais atendendo na sua conta.'),
    product('prod_stub_unit', 'Adicional de Unidade',
            'Uma unidade / franquia adicional gerenciada na mesma conta.'),
    product('prod_stub_text_msg', 'Mensagens de Texto',
            'Excedente de mensagens de texto — cobrado por unidade enviada.'),
    product('prod_stub_audio_msg_basic', 'Mensagens de Áudio',
            'Excedente de mensagens de áudio — cobrado por unidade transcrita.'),
    product('prod_stub_audio_msg_premium', 'Mensagens de Áudio (Premium)',
            'Excedente de áudio com transcrição premium — maior fidelidade.'),
    product('prod_stub_token_pack_5k', 'Pacote Tokens 5k',
            'Pacote mensal de 5.000 tokens de IA para consumo da conta.'),
    product('prod_stub_media_answer', 'Respostas a imagens, arquivos e transcrições',
            'Cobrança por resposta processada sobre uma mídia enviada pelo cliente.'),
    product('prod_stub_tokens', 'Tokens',
            'Tokens de IA cobrados sob demanda.'),
    product('prod_stub_implementation_standard', 'Implantação',
            'Configuração inicial completa da conta com acompanhamento.',
            category: 'addon'),
    product('prod_stub_implementation_lite', 'Implantação Lite',
            'Configuração inicial guiada, versão enxuta.', category: 'addon'),
    product('prod_stub_api_integration', 'Integração via API',
            'Integração personalizada com sistemas do cliente via API.', category: 'addon')
  ].freeze

  # Prices are ordered plan-first, then the recurring add-ons, then the
  # one-off items — the picker sorts by usage_count and product name so
  # the screen order is not this one, but declaring it this way keeps
  # the file easy to scan.
  PRICES = [
    # Plataforma Auris — três ciclos de assinatura
    price('price_stub_platform_monthly', 'prod_stub_platform', 129_700, recurring: MONTHLY),
    price('price_stub_platform_semiannual', 'prod_stub_platform', 598_200, recurring: SEMIANNUAL),
    price('price_stub_platform_annual', 'prod_stub_platform', 1_076_400, recurring: ANNUAL),

    # Adicional de Canal — três ciclos
    price('price_stub_channel_monthly', 'prod_stub_channel', 6_900, recurring: MONTHLY),
    price('price_stub_channel_semiannual', 'prod_stub_channel', 41_400, recurring: SEMIANNUAL),
    price('price_stub_channel_annual', 'prod_stub_channel', 74_520, recurring: ANNUAL),

    # Adicional de Profissional — preço em faixas (graduado no mensal,
    # volume nos ciclos longos), casando com o que existe no Stripe real.
    tiered_price('price_stub_professional_monthly', 'prod_stub_professional', [
                   { up_to: 8,  unit_amount: 5_900, flat_amount: nil },
                   { up_to: 29, unit_amount: 2_900, flat_amount: nil },
                   { up_to: 59, unit_amount: 1_900, flat_amount: nil },
                   { up_to: nil, unit_amount: 900,  flat_amount: nil }
                 ], recurring: MONTHLY, mode: 'graduated'),
    tiered_price('price_stub_professional_semiannual', 'prod_stub_professional', [
                   { up_to: 8,  unit_amount: 35_400, flat_amount: nil },
                   { up_to: 29, unit_amount: 17_400, flat_amount: nil },
                   { up_to: 59, unit_amount: 11_400, flat_amount: nil },
                   { up_to: nil, unit_amount: 5_400,  flat_amount: nil }
                 ], recurring: SEMIANNUAL, mode: 'volume'),
    tiered_price('price_stub_professional_annual', 'prod_stub_professional', [
                   { up_to: 8,  unit_amount: 63_720, flat_amount: nil },
                   { up_to: 29, unit_amount: 31_320, flat_amount: nil },
                   { up_to: 59, unit_amount: 20_520, flat_amount: nil },
                   { up_to: nil, unit_amount: 9_720,  flat_amount: nil }
                 ], recurring: ANNUAL, mode: 'volume'),

    # Adicional de Unidade — três ciclos
    price('price_stub_unit_monthly', 'prod_stub_unit', 19_900, recurring: MONTHLY),
    price('price_stub_unit_semiannual', 'prod_stub_unit', 119_400, recurring: SEMIANNUAL),
    price('price_stub_unit_annual', 'prod_stub_unit', 214_920, recurring: ANNUAL),

    # Excedentes — cobrados mensal por unidade
    price('price_stub_text_msg_monthly', 'prod_stub_text_msg', 6, recurring: MONTHLY),
    price('price_stub_audio_msg_basic_monthly', 'prod_stub_audio_msg_basic', 49, recurring: MONTHLY),
    price('price_stub_audio_msg_premium_monthly', 'prod_stub_audio_msg_premium', 71, recurring: MONTHLY),
    price('price_stub_media_answer_monthly', 'prod_stub_media_answer', 10, recurring: MONTHLY),

    # Pacote e tokens
    price('price_stub_token_pack_5k_monthly', 'prod_stub_token_pack_5k', 30_000, recurring: MONTHLY),
    price('price_stub_tokens_monthly', 'prod_stub_tokens', 0, recurring: MONTHLY),

    # Avulsos (recurring nil)
    price('price_stub_implementation_standard_oneoff', 'prod_stub_implementation_standard', 300_000),
    price('price_stub_implementation_lite_oneoff', 'prod_stub_implementation_lite', 100_000),
    price('price_stub_api_integration_oneoff', 'prod_stub_api_integration', 199_900)
  ].freeze

  COUPONS = [
    Coupon.new(id: 'stub_parceiro', name: 'Parceiro', percent_off: 15, amount_off: nil, currency: 'brl', valid: true),
    Coupon.new(id: 'stub_black', name: 'Black Friday', percent_off: 25, amount_off: nil, currency: 'brl', valid: true),
    Coupon.new(id: 'stub_indicacao', name: 'Indicação', percent_off: nil, amount_off: 5_000, currency: 'brl', valid: true)
  ].freeze
end

Rails.application.config.after_initialize do
  Integrations::Stripe::Client.class_eval do
    define_method(:configured?) { true }

    define_method(:list_products) do |limit: nil, active: nil|
      list = SalesStripeStub::PRODUCTS
      list = list.select(&:active) if active
      SalesStripeStub::List.new(limit ? list.first(limit) : list)
    end

    define_method(:list_prices) do |product_id: nil, limit: nil|
      list = SalesStripeStub::PRICES
      list = list.select { |price| price.product == product_id } if product_id
      SalesStripeStub::List.new(limit ? list.first(limit) : list)
    end

    define_method(:list_coupons) do |limit: nil|
      SalesStripeStub::List.new(limit ? SalesStripeStub::COUPONS.first(limit) : SalesStripeStub::COUPONS)
    end
  end
end
