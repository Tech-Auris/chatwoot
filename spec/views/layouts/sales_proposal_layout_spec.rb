require 'rails_helper'

# The prospect's page is rendered by Rails, so its stylesheet has to be a real
# Vite entrypoint. In development the dev server serves whatever name is asked
# for, which is why a name that does not exist stays invisible until the built
# assets are looked up in production — and there it answers 500 on every visit.
RSpec.describe 'layouts/sales_proposal', type: :view do
  it 'points at an entrypoint that exists' do
    layout = Rails.root.join('app/views/layouts/sales_proposal.html.erb').read
    entrypoint = layout[/vite_stylesheet_tag '([^']+)'/, 1]

    expect(entrypoint).to be_present
    expect(Dir[Rails.root.join("app/javascript/entrypoints/#{entrypoint}.*")]).not_to be_empty
  end
end
