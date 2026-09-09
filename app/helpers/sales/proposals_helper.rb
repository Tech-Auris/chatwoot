# Dates and deadlines as the prospect reads them.
#
# Written here rather than through `l` and `distance_of_time_in_words`: those
# answer in the request's locale, and the app registers Brazilian Portuguese as
# `pt_BR` while rails-i18n ships its date formats under `pt-BR`, so the page
# fell back to English — "August 31, 2028" and "about 2 years" on a page written
# entirely in Portuguese.
module Sales::ProposalsHelper
  # Amounts are stored in cents and read in reais, with the separators used
  # here: the default locale prints "R$3,000.00", which a Brazilian reader can
  # take for three reais.
  def proposal_amount(cents)
    number_to_currency((cents || 0) / 100.0, unit: 'R$ ', separator: ',', delimiter: '.')
  end

  # The sales flow carries a mark of its own — the prospect is not a user of the
  # product yet — and falls back to the product's while none is configured, so
  # the page is never left without one.
  def proposal_logo_url
    GlobalConfig.get('SALES_PROPOSAL_LOGO')['SALES_PROPOSAL_LOGO'].presence ||
      GlobalConfig.get('LOGO')['LOGO'].presence ||
      '/brand-assets/logo.svg'
  end

  def proposal_brand_name
    GlobalConfig.get('INSTALLATION_NAME')['INSTALLATION_NAME'].presence || 'AurisChat'
  end

  # The company's own static PIX code, configured once in Settings, carrying the
  # total of this proposal — so the customer confirms an amount instead of
  # typing one they read minutes ago.
  def pix_payload(proposal)
    configured = GlobalConfig.get('SALES_PIX_PAYLOAD')['SALES_PIX_PAYLOAD'].presence
    return nil if configured.blank?

    Sales::PixCodeService.new(payload: configured, amount_cents: proposal.total_amount).perform
  end

  # Drawn from the code itself rather than stored as an image, so the QR and the
  # copy-and-paste code can never be of two different accounts.
  def pix_qr_code(payload)
    svg = RQRCode::QRCode.new(payload).as_svg(module_size: 4, standalone: true, use_path: true)
    "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
  end

  # The number the proposal was registered against, with the four digits the
  # page is asking for left out: a lead is often created by the clinic's
  # secretary, and the customer has no way of telling whose number it is
  # without seeing the beginning of it.
  def proposal_masked_phone(phone)
    prefix = proposal_phone_prefix(phone)
    prefix && "#{prefix}XXXX"
  end

  # Everything but the four digits the page is asking for: "(61) 99844-".
  def proposal_phone_prefix(phone)
    digits = phone.to_s.gsub(/\D/, '')
    digits = digits.delete_prefix('55') if digits.length > 11 && digits.start_with?('55')
    return nil if digits.length < 10

    "(#{digits[0, 2]}) #{digits[2...-4]}-"
  end

  # The label the prospect reads next to each item on the plan page, so
  # they know what recurrence they are signing for. A recurring item
  # follows the whole quote's billing_cycle (a monthly plan comes with
  # monthly add-ons); an item with no interval is a one-off.
  BILLING_CYCLE_LABELS = { 'monthly' => 'mensal', 'semiannual' => 'semestral', 'annual' => 'anual' }.freeze
  def proposal_item_period(item, proposal)
    return 'avulso' if item.recurring_interval.blank?

    BILLING_CYCLE_LABELS[proposal.billing_cycle.to_s] || item.recurring_interval
  end

  def proposal_datetime(time)
    return nil if time.blank?

    "#{time.strftime('%d/%m/%Y')} às #{time.strftime('%H:%M')}"
  end

  # How much longer the reservation holds, counted in days — which is how a
  # deadline is read when the answer decides whether to sign today.
  def proposal_time_left(deadline)
    days = (deadline.to_date - Date.current).to_i

    case days
    when ..0 then 'menos de um dia'
    when 1 then 'mais um dia'
    else "mais #{days} dias"
    end
  end

  # The "or in 12x" hint on the plan/reservation card. Reads the natural
  # split for the billing cycle (semiannual → 6, annual → 12); monthly
  # plans return nil because the recurrence itself is the split.
  BILLING_CYCLE_INSTALLMENTS = { 'semiannual' => 6, 'annual' => 12 }.freeze

  def proposal_installment_hint(proposal)
    return nil if proposal.billing_cycle.blank?

    parts = BILLING_CYCLE_INSTALLMENTS[proposal.billing_cycle]
    return nil if parts.blank?

    "#{parts}x de #{proposal_amount((proposal.total_amount || 0) / parts)} no cartão"
  end

  # The "or à vista" hint for plans that carry a PIX discount (semiannual
  # 5%, annual 10%). Returns a hash `{ amount:, percent: }` with the
  # already-discounted total in cents and the discount percent, or nil for
  # plans that offer no à-vista discount (monthly today).
  def proposal_pix_cash_hint(proposal)
    return nil if proposal.billing_cycle.blank?

    percent = Sales::CheckoutService.pix_discount_for(proposal.billing_cycle)
    return nil if percent.to_i.zero?

    total = proposal.total_amount || 0
    discounted = total - ((total * percent) / 100.0).round
    { amount: discounted, percent: percent }
  end
end
