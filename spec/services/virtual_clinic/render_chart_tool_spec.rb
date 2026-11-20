require 'rails_helper'

RSpec.describe VirtualClinic::RenderChartTool do
  let(:charts) { [] }
  let(:tool) { described_class.new(charts) }
  let(:weekdays) { %w[seg ter qua qui sex] }

  it 'keeps a valid chart for the answer' do
    result = tool.execute(type: 'bar', title: 'Faltas por dia (1–18/nov)', labels: weekdays,
                          series: [{ 'name' => 'Faltas', 'data' => [3, 1, 0, 2, 5] }])

    expect(result).to eq(described_class::READY)
    expect(charts).to eq([{ 'type' => 'bar', 'title' => 'Faltas por dia (1–18/nov)', 'labels' => weekdays,
                            'series' => [{ 'name' => 'Faltas', 'data' => [3, 1, 0, 2, 5] }] }])
  end

  it 'refuses a chart that does not add up, so the model can fix it' do
    expect(tool.execute(type: 'pie', title: 'x', labels: weekdays, series: [{ 'name' => 'a', 'data' => [1] * 5 }]))
      .to eq({ error: 'Use type bar ou line.' })
    expect(tool.execute(type: 'line', title: 'x', labels: weekdays, series: [{ 'name' => 'a', 'data' => [1, 2] }]))
      .to eq({ error: 'Cada série precisa de um número para cada rótulo.' })
    expect(tool.execute(type: 'line', title: 'x', labels: weekdays, series: [{ 'name' => 'a', 'data' => [1, 2, 'três', 4, 5] }]))
      .to eq({ error: 'Cada série precisa de um número para cada rótulo.' })
    expect(tool.execute(type: 'bar', title: 'x', labels: [], series: [])).to eq({ error: 'Use de 1 a 31 rótulos.' })
    expect(charts).to be_empty
  end
end
