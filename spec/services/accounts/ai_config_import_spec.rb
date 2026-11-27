require 'rails_helper'

RSpec.describe Accounts::AiConfigImport do
  let(:account) { create(:account) }
  let!(:internal_account) { Account.find_by(id: 66) || create(:account, id: 66) }
  let(:csv_path) { Rails.root.join('tmp', "ai_config_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id name_owner prompt_identity bounce_seconds flag_audio_on_off phone_alert chatwoot_id_conversa_alerta
                mensagem_de_escala_para_o_usuario time_padrao_de_escala]
      csv << [account.id, 'Dra. Ana', 'Você é Lia', '0', 'true', '5511999999999', '1234', 'Já te passo para a equipe.', '29']
      csv << [151, 'Auris', '', nil, nil, nil, nil, nil, nil]
      csv << [999_999, 'X', 'Você é Iris', '40', 'true', nil, nil, nil, '11']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'imports the AI columns with their types, blank cells as nil (the audio flag as true), mapping the internal clients' do
    results = described_class.new(csv_path: csv_path, apply: true).perform

    expect(account.reload.ai_config).to eq(
      'prompt_identity' => 'Você é Lia', 'bounce_seconds' => 0, 'flag_audio_on_off' => true,
      'chatwoot_id_conversa_alerta' => 1234, 'mensagem_de_escala_para_o_usuario' => 'Já te passo para a equipe.', 'time_padrao_de_escala' => 29
    )
    expect(internal_account.reload.ai_config).to include('prompt_identity' => nil, 'flag_audio_on_off' => true)
    expect(results.map { |result| [result.account_id, result.differences, result.error] })
      .to eq([[account.id, [], nil], [66, [], nil], [999_999, nil, 'conta não encontrada']])
  end

  it 'only compares on a dry run, reporting the keys that differ' do
    account.update!(ai_config: { prompt_identity: 'Você é Lia', bounce_seconds: 35, flag_audio_on_off: false })

    results = described_class.new(csv_path: csv_path).perform

    expect(account.reload.ai_config['bounce_seconds']).to eq(35)
    expect(results.first.differences).to eq(%w[bounce_seconds flag_audio_on_off chatwoot_id_conversa_alerta
                                               mensagem_de_escala_para_o_usuario time_padrao_de_escala])
    expect(results.second.differences).to eq(['sem ai_config'])
  end
end
