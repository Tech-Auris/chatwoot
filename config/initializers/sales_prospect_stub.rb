# Dev-only stub for the ClickUp prospect list. When
# CLICKUP_PROSPECT_STUB=1 is set, Sales::ClickupProspectSearchService
# reads from a fixed fixture instead of walking the pipeline through
# graph.clickup.com — useful to exercise the "Montar plano" search and
# the reservation-sync flow without a valid ClickUp token, without
# CLICKUP_PIPELINE_LIST_ID configured, and without touching real deals.
#
# Never active in production. Rows here span open statuses (search
# picks them up) and closed ones (`ganho`/`perdido`, which `find` still
# resolves for the Reservations sync).
return unless Rails.env.development? && ENV['CLICKUP_PROSPECT_STUB'] == '1'

CLICKUP_STUB_PROSPECTS = [
  { task_id: 'STUB_gustavo_teste', name: 'Gustavo Teste', clinic_name: 'Clínica Teste',
    email: 'gustavo@clinicateste.com.br', phone: '+55 61 99272-0350',
    status: 'novo lead', status_color: '#3498db', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_gustavo_fraga', name: 'Gustavo Fraga', clinic_name: nil,
    email: 'gustavo@fraga.com.br', phone: '+55 11 98077-6650',
    status: 'fup 1', status_color: '#e67e22', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_camila_vieira', name: 'Camila Vieira', clinic_name: 'Clínica Vieira',
    email: 'camila@clinicavieira.com.br', phone: '+55 51 99123-4567',
    status: 'em análise', status_color: '#9b59b6', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_rafael_cardoso', name: 'Rafael Cardoso', clinic_name: nil,
    email: nil, phone: '+55 21 98844-2211',
    status: 'proposta enviada', status_color: '#f39c12', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_beatriz_prado', name: 'Beatriz Prado', clinic_name: 'Clínica Prado',
    email: 'beatriz@clinicaprado.com.br', phone: '+55 31 99988-7766',
    status: 'em análise', status_color: '#9b59b6', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_marcos_aurelio', name: 'Marcos Aurélio', clinic_name: 'Clínica Aurélio',
    email: 'marcos@clinicaaurelio.com.br', phone: '+55 47 99555-4433',
    status: 'assinou', status_color: '#2ecc71', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_isabela_nunes', name: 'Isabela Nunes', clinic_name: 'Clínica Nunes',
    email: 'isabela@clinicanunes.com.br', phone: '+55 62 99321-8877',
    status: 'pago', status_color: '#27ae60', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_lucas_almeida', name: 'Lucas Almeida', clinic_name: 'Clínica Almeida',
    email: 'lucas@clinicaalmeida.com.br', phone: '+55 41 99765-4321',
    status: 'ganho', status_color: '#16a085', due_date: nil, url: 'https://app.clickup.com/t/stub' },
  { task_id: 'STUB_fernanda_costa', name: 'Fernanda Costa', clinic_name: nil,
    email: 'fernanda@costa.com.br', phone: '+55 85 99444-2211',
    status: 'perdido', status_color: '#c0392b', due_date: nil, url: 'https://app.clickup.com/t/stub' }
].freeze

Rails.application.config.after_initialize do
  Sales::ClickupProspectSearchService.class_eval do
    define_method(:prospects) { CLICKUP_STUB_PROSPECTS }
    # `list_id` would still raise NotConfigured without a real GlobalConfig
    # entry — override it so the stub works on a fresh dev DB.
    define_method(:list_id) { 'STUB_LIST' }
  end
end
