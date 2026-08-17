# Suggests which Stripe customer an AurisChat account probably belongs to.
#
# Deliberately advisory: the reconciliation screen shows the candidates and the
# reason behind each one, and a human confirms. Auto-linking is the wrong
# trade-off here — a wrong pairing bills the wrong customer, and today the
# emails on both sides frequently disagree.
#
# Rules, strongest first:
#   1. an administrator's email matches the customer email exactly
#   2. the email domain matches (same company, different person)
#   3. the normalized names match (accents, case and punctuation ignored)
class Financial::StripeCustomerMatcher
  # Free/consumer providers say nothing about which company a customer is, so a
  # domain hit on them is noise rather than a signal.
  GENERIC_DOMAINS = %w[gmail.com hotmail.com outlook.com yahoo.com yahoo.com.br icloud.com live.com bol.com.br uol.com.br].freeze

  REASONS = {
    email: 'E-mail do administrador confere',
    domain: 'Mesmo domínio de e-mail',
    name: 'Nome parecido'
  }.freeze

  MAX_SUGGESTIONS = 3

  def initialize(customers)
    @customers = Array(customers)
  end

  # @return [Array<Hash>] candidates ordered by strength, capped at MAX_SUGGESTIONS
  def suggestions_for(account, admin_emails)
    emails = Array(admin_emails).compact_blank.map { |email| email.to_s.downcase.strip }

    candidates = @customers.filter_map { |customer| score(customer, account, emails) }
    candidates.sort_by { |candidate| [candidate[:rank], candidate[:name].to_s.downcase] }
              .first(MAX_SUGGESTIONS)
  end

  private

  def score(customer, account, emails)
    reason = match_reason(customer, account, emails)
    return nil if reason.nil?

    {
      id: customer.id,
      name: customer.name,
      email: customer.email,
      reason: REASONS[reason],
      rank: REASONS.keys.index(reason)
    }
  end

  def match_reason(customer, account, emails)
    customer_email = customer.email.to_s.downcase.strip

    return :email if customer_email.present? && emails.include?(customer_email)
    return :domain if domain_match?(customer_email, emails)
    return :name if normalize(customer.name) == normalize(account.name) && normalize(account.name).present?

    nil
  end

  def domain_match?(customer_email, emails)
    domain = domain_of(customer_email)
    return false if domain.blank? || GENERIC_DOMAINS.include?(domain)

    emails.any? { |email| domain_of(email) == domain }
  end

  def domain_of(email)
    email.to_s.split('@').last.to_s.downcase.presence
  end

  # "Clínica São José Ltda." and "clinica sao jose ltda" are the same customer
  # as far as a human reconciling the two lists is concerned.
  def normalize(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, '')
  end
end
