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
    digits = phone.to_s.gsub(/\D/, '')
    digits = digits.delete_prefix('55') if digits.length > 11 && digits.start_with?('55')
    return nil if digits.length < 10

    "(#{digits[0, 2]}) #{digits[2...-4]}-XXXX"
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
end
