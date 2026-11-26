require 'spec_helper'
require 'yaml'
require_relative '../../lib/fazer_ai_sync'

RSpec.describe FazerAiSync do
  def record(hash, subject, body = '')
    [hash, '2026-11-20', subject, body].join(described_class::FIELD_SEP) + described_class::RECORD_SEP
  end

  let(:raw) do
    record('aaa1111', 'feat(filters): filter by missing custom attribute (#352)') +
      record('bbb2222', 'Merge pull request #665 from fazer-ai/feat/email-continue', "feat(email): continue the open case\n") +
      record('ccc3333', 'Merge pull request #1008 from fazer-ai/chore/merge-upstream-4.20.1', "chore: merge upstream v4.20.1\n") +
      record('ddd4444', 'chore: restore upstream v4.16.2 ancestry (squashed in #348)') +
      record('eee5555', 'docs: record the merge strategy')
  end
  let(:entries) { described_class.parse_log(raw) }

  describe '.parse_log' do
    it 'reads squash PRs, merge PRs, upstream syncs and loose commits' do
      expect(entries.map { |e| [e.kind, e.key] }).to eq(
        [[:pr, 352], [:pr, 665], [:upstream, '4.20.1'], [:upstream, '4.16.2'], [:commit, 'eee5555']]
      )
    end

    it 'strips the PR number from a squash title and takes a merge title from its body' do
      expect(entries[0].title).to eq('feat(filters): filter by missing custom attribute')
      expect(entries[1].title).to eq('feat(email): continue the open case')
    end
  end

  describe '#status_for' do
    let(:sync) do
      described_class.new(
        'prs' => { 352 => { 'status' => 'trazido', 'auris_pr' => 978 } },
        'upstream' => { '4.20.1' => { 'status' => 'trazer' } },
        'commits' => { 'eee5555' => { 'status' => 'nao_trazer', 'motivo' => 'docs internos' } }
      )
    end

    it 'uses the registry decision and treats everything else as pending' do
      expect(entries.map { |e| sync.status_for(e) }).to eq(%w[trazido pendente trazer pendente nao_trazer])
    end

    it 'counts entries per status' do
      expect(sync.summary(entries)).to eq('trazido' => 1, 'pendente' => 2, 'trazer' => 1, 'nao_trazer' => 1)
    end
  end

  it 'loads the committed registry with known statuses only' do
    registry = YAML.safe_load_file(File.expand_path('../../.github/fazer-ai-sync.yml', __dir__))
    statuses = registry.values_at('prs', 'upstream', 'commits').compact.flat_map(&:values).map { |d| d['status'] }

    expect(statuses - described_class::STATUSES).to be_empty
  end
end
