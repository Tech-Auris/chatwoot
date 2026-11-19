class CreateSecretaryPrompts < ActiveRecord::Migration[7.1]
  def change
    create_table :secretary_prompts do |t|
      t.text :core_behavior
      t.text :communication_rules
      t.text :medical_compliance
      t.text :tools_usage
      t.timestamps
    end
  end
end
