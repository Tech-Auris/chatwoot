# What all the OpenAI calls of an answer spent (every round of tools and the
# retry): input and output tokens become the sum of the calls, plus the cached
# input, how many calls and the price in US$. The base for the Auris Agents
# credits.
class AddUsageToVirtualClinicMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :virtual_clinic_messages, :cached_tokens, :integer
    add_column :virtual_clinic_messages, :llm_calls, :integer
    add_column :virtual_clinic_messages, :cost_usd, :decimal, precision: 12, scale: 6
  end
end
