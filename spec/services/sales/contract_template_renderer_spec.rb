require 'rails_helper'

RSpec.describe Sales::ContractTemplateRenderer do
  let(:content) { '{{#se_pj}}PJ: {{razao_social}}{{/se_pj}}{{#se_pf}}PF: {{nome_completo}}{{/se_pf}} | {{produtos}} | {{desconhecido}}' }

  def render(person_type, variables)
    described_class.new(content: content, variables: variables, person_type: person_type).render
  end

  it 'keeps only the block of the person type and fills the fields' do
    html = render('pj', razao_social: 'Clínica <Exemplo>', produtos: '<ul><li>Plano</li></ul>')

    expect(html).to eq('PJ: Clínica &lt;Exemplo&gt; | <ul><li>Plano</li></ul> | {{desconhecido}}')
  end

  it 'renders the PF block for a person' do
    expect(render('pf', nome_completo: 'Ana', produtos: '')).to start_with('PF: Ana |')
  end
end
