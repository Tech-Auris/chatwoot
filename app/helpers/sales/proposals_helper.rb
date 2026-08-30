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
