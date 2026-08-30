require 'rails_helper'

# The prospect's page is rendered by Rails, so its assets have to resolve
# against the built manifest — and that only happens in production: the dev
# server answers for any name that is asked of it, so a name Vite never built
# looks fine locally and answers 500 on every visit once deployed.
#
# Vite files an entrypoint in the manifest under its own extension, and the tag
# helper appends the one it expects: `vite_javascript_tag 'x'` looks up
# `entrypoints/x.js`. A stylesheet entrypoint is filed as `.scss` while
# `vite_stylesheet_tag` asks for `.css`, which never matches — hence the
# JavaScript entrypoint that imports the stylesheet.
RSpec.describe 'layouts/sales_proposal', type: :view do
  let(:layout) { Rails.root.join('app/views/layouts/sales_proposal.html.erb').read }

  it 'loads its assets through a javascript entrypoint' do
    expect(layout).to include("vite_javascript_tag 'sales_proposal'")
    expect(layout).not_to include('vite_stylesheet_tag')
  end

  it 'points at an entrypoint that exists under the name vite will look up' do
    entrypoint = layout[/vite_javascript_tag '([^']+)'/, 1]

    expect(Rails.root.join("app/javascript/entrypoints/#{entrypoint}.js")).to exist
  end
end
