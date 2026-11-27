require 'rails_helper'

RSpec.describe Accounts::ClienteImport do
  let(:account) { create(:account, name: 'Clínica no AurisChat') }
  let!(:internal_account) { Account.find_by(id: 66) || create(:account, id: 66) }
  let(:csv_path) { Rails.root.join('tmp', "cliente_import_#{SecureRandom.hex(4)}.csv") }

  def write_csv(headers, *rows)
    CSV.open(csv_path, 'w') do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end

  after { FileUtils.rm_f(csv_path) }

  context 'with the AI setup columns' do
    before do
      write_csv(%w[id prompt_identity bounce_seconds flag_audio_on_off phone_alert chatwoot_id_conversa_alerta
                   mensagem_de_escala_para_o_usuario time_padrao_de_escala calendar_instructions mensagens_fixas],
                [account.id, 'Você é Lia', '0', 'true', '5511999999999', '1234', 'Já te passo para a equipe.', '29',
                 'Agende só de manhã', '{"Vim pelo anúncio","Quero o cupom, por favor"}'],
                [151, '', nil, 'false', nil, nil, nil, nil, nil, nil],
                [999_999, 'Você é Iris', '40', 'true', nil, nil, nil, '11', nil, nil])
    end

    it 'imports them with their types, blank cells as nil, mapping the internal clients' do
      results = described_class.new(csv_path: csv_path, apply: true).perform

      expect(account.reload.ai_config).to eq(
        'prompt_identity' => 'Você é Lia', 'bounce_seconds' => 0, 'flag_audio_on_off' => true, 'chatwoot_id_conversa_alerta' => 1234,
        'mensagem_de_escala_para_o_usuario' => 'Já te passo para a equipe.', 'time_padrao_de_escala' => 29,
        'calendar_instructions' => 'Agende só de manhã', 'mensagens_fixas' => ['Vim pelo anúncio', 'Quero o cupom, por favor']
      )
      expect(internal_account.reload.ai_config).to include('prompt_identity' => nil, 'flag_audio_on_off' => false)
      expect(results.map { |result| [result.account_id, result.differences, result.error] })
        .to eq([[account.id, [], nil], [66, [], nil], [999_999, nil, 'conta não encontrada']])
    end

    it 'only compares on a dry run, reporting the columns that differ' do
      account.update!(ai_config: { prompt_identity: 'Você é Lia', bounce_seconds: 35 })

      results = described_class.new(csv_path: csv_path).perform

      expect(account.reload.ai_config['bounce_seconds']).to eq(35)
      expect(results.first.differences).to eq(%w[bounce_seconds flag_audio_on_off chatwoot_id_conversa_alerta mensagem_de_escala_para_o_usuario
                                                 time_padrao_de_escala calendar_instructions mensagens_fixas])
      expect(results.second.differences).to match_array(%w[prompt_identity bounce_seconds flag_audio_on_off chatwoot_id_conversa_alerta
                                                           mensagem_de_escala_para_o_usuario time_padrao_de_escala calendar_instructions
                                                           mensagens_fixas])
    end
  end

  it 'imports only the columns in the CSV, keeping the rest of the AI setup and the account name' do
    account.update!(ai_config: { prompt_identity: 'Você é Lia', bounce_seconds: 35 })
    write_csv(%w[id name_institution name_owner phone_contact email_contact mensagens_fixas],
              [account.id, 'Nome no Supabase', 'Dra. Ana', '+5511988887777', '', '["Vim pelo anúncio"]'])

    results = described_class.new(csv_path: csv_path, apply: true).perform

    account.reload
    expect(account).to have_attributes(name: 'Clínica no AurisChat', name_owner: 'Dra. Ana', phone_contact: '+5511988887777', email_contact: nil)
    expect(account.ai_config).to include('prompt_identity' => 'Você é Lia', 'bounce_seconds' => 35, 'mensagens_fixas' => ['Vim pelo anúncio'])
    expect(results.first.differences).to eq([])
  end
end
