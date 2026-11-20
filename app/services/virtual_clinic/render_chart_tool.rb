# Lets the manager answer with a bar or line chart (evolution over time,
# campaigns side by side, no-shows per weekday). The chart is data, checked
# here and drawn by the dashboard next to the text, with the numbers in a
# "ver dados" table.
class VirtualClinic::RenderChartTool < RubyLLM::Tool
  TYPES = %w[bar line].freeze
  MAX_LABELS = 31
  MAX_SERIES = 4
  READY = 'Gráfico pronto: ele aparece junto da sua resposta. Agora escreva a resposta em texto, sem repetir todos os números.'.freeze

  def initialize(charts)
    super()
    @charts = charts
  end

  def name
    'render_chart'
  end

  def description
    'Desenha um gráfico de barras ou de linha na conversa, com números que você já buscou nas outras ferramentas. ' \
      'Use para evolução no tempo, comparação entre campanhas ou períodos e distribuições (ex.: faltas por dia da semana).'
  end

  def params_schema
    {
      'type' => 'object',
      'properties' => {
        'type' => { 'type' => 'string', 'enum' => TYPES },
        'title' => { 'type' => 'string', 'description' => 'Título curto, com o período.' },
        'labels' => { 'type' => 'array', 'items' => { 'type' => 'string' }, 'description' => 'Rótulos do eixo X.' },
        'series' => {
          'type' => 'array',
          'items' => { 'type' => 'object', 'properties' => { 'name' => { 'type' => 'string' },
                                                             'data' => { 'type' => 'array', 'items' => { 'type' => 'number' } } },
                       'required' => %w[name data] }
        }
      },
      'required' => %w[type title labels series]
    }
  end

  def execute(type:, title:, labels:, series:)
    chart = { 'type' => type, 'title' => title.to_s, 'labels' => Array(labels).map(&:to_s),
              'series' => Array(series).map { |item| { 'name' => item['name'].to_s, 'data' => Array(item['data']) } } }
    problem = problem(chart)
    return { error: problem } if problem

    @charts << chart
    READY
  end

  private

  def problem(chart)
    return "Use type #{TYPES.join(' ou ')}." unless TYPES.include?(chart['type'])
    return "Use de 1 a #{MAX_LABELS} rótulos." unless chart['labels'].size.between?(1, MAX_LABELS)
    return "Use de 1 a #{MAX_SERIES} séries." unless chart['series'].size.between?(1, MAX_SERIES)

    'Cada série precisa de um número para cada rótulo.' unless chart['series'].all? do |item|
      item['data'].size == chart['labels'].size && item['data'].all?(Numeric)
    end
  end
end
