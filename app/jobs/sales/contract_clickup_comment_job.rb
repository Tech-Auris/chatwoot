# Posts the contract comment (generated / signed) on the deal's ClickUp task.
# A ClickUp hiccup never blocks the contract: it is logged and dropped.
class Sales::ContractClickupCommentJob < ApplicationJob
  queue_as :low

  def perform(contract_id, kind)
    contract = SalesContract.find(contract_id)
    task_id = contract.sales_quote.clickup_task_id
    client = Integrations::Clickup::Client.new
    return if task_id.blank? || !client.configured?

    client.add_comment(task_id, Sales::ContractClickupComment.public_send(kind, contract))
  rescue Integrations::Clickup::Client::Error => e
    Rails.logger.warn("[sales] contract #{kind} comment not posted: #{e.message}")
  end
end
