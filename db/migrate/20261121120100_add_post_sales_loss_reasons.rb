# Loss reasons that only make sense once a contact follows a clinic pipeline
# (post-sales): the patient moved on to something else, or asked to stop
# receiving messages. The list stays global, shared with the Agendamento.
class AddPostSalesLossReasons < ActiveRecord::Migration[7.1]
  REASONS = ['Trocou de interesse', 'Pediu para não receber mensagens'].freeze

  def up
    next_position = (LossReason.maximum(:position) || -1) + 1
    REASONS.each_with_index do |name, index|
      LossReason.find_or_create_by!(name: name) do |reason|
        reason.position = next_position + index
        reason.active = true
      end
    end
  end

  def down
    LossReason.where(name: REASONS).destroy_all
  end
end
