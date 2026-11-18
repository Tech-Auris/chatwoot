require 'administrate/field/base'

# A list of inbox ids picked from a multi-select of inboxes. On a record that
# already has an account it lists only that account's inboxes; otherwise every
# inbox, grouped by account.
class InboxIdsField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => [] }
  end

  def inboxes
    Inbox.where(id: data).order(:id)
  end

  def to_s
    inboxes.map { |inbox| label(inbox) }.join(', ')
  end

  def grouped_options
    scope = resource.account_id ? Inbox.where(account_id: resource.account_id) : Inbox.all
    scope.includes(:account).order(:account_id, :name).group_by(&:account).map do |account, inboxes|
      ["#{account.name} (##{account.id})", inboxes.map { |inbox| [label(inbox), inbox.id] }]
    end
  end

  private

  def label(inbox)
    "#{inbox.name} (##{inbox.id})"
  end
end
