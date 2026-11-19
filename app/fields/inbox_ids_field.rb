require 'administrate/field/base'

# A list of inbox ids, picked as removable tags from the inboxes of the record's
# account. The form switches the inbox list when the account changes.
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

  # The account's inboxes, as select options.
  def options
    return [] unless resource.account_id

    Inbox.where(account_id: resource.account_id).order(:name).map { |inbox| [label(inbox), inbox.id] }
  end

  # Every inbox, for the form to list the ones of the account picked.
  def all_inboxes
    Inbox.order(:name).map { |inbox| { value: inbox.id, text: label(inbox), account_id: inbox.account_id } }
  end

  private

  def label(inbox)
    "#{inbox.name} (##{inbox.id})"
  end
end
