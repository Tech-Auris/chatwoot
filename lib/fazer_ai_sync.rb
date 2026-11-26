# Classifies the first-parent history of fazer-ai/chatwoot main against our
# registry (.github/fazer-ai-sync.yml). GitHub's "commits behind" counts git
# ancestry, so a hand port never leaves it; the registry is the source of truth.
class FazerAiSync
  Entry = Struct.new(:kind, :key, :sha, :date, :title, keyword_init: true)

  STATUSES = %w[trazido trazer nao_trazer].freeze
  FIELD_SEP = "\x1f".freeze
  RECORD_SEP = "\x1e".freeze
  LOG_FORMAT = '%h%x1f%as%x1f%s%x1f%b%x1e'.freeze

  def self.parse_log(raw)
    raw.split(RECORD_SEP).map(&:strip).reject(&:empty?).map { |record| parse_record(record) }
  end

  def self.parse_record(record)
    hash, date, subject, body = record.split(FIELD_SEP, 4)
    if (version = upstream_version(subject))
      Entry.new(kind: :upstream, key: version, sha: hash, date: date, title: subject)
    elsif (merge = subject.match(/\AMerge pull request #(\d+) from /))
      title = body.to_s.lines.first.to_s.strip
      Entry.new(kind: :pr, key: merge[1].to_i, sha: hash, date: date, title: title.empty? ? subject : title)
    elsif (pr = subject.match(/\(#(\d+)\)\z/))
      Entry.new(kind: :pr, key: pr[1].to_i, sha: hash, date: date, title: subject.sub(/\s*\(#\d+\)\z/, ''))
    else
      Entry.new(kind: :commit, key: hash, sha: hash, date: date, title: subject)
    end
  end

  def self.upstream_version(subject)
    subject[%r{from fazer-ai/chore/merge-upstream-(\d+\.\d+\.\d+)}, 1] ||
      subject[/\Achore: restore upstream v(\d+\.\d+\.\d+) ancestry/, 1] ||
      subject[/\Achore: merge upstream v(\d+\.\d+\.\d+)/, 1]
  end

  def initialize(registry)
    @prs = (registry['prs'] || {}).transform_keys(&:to_i)
    @commits = registry['commits'] || {}
    @upstream = registry['upstream'] || {}
  end

  def status_for(entry)
    decision_for(entry)&.fetch('status', nil) || 'pendente'
  end

  def decision_for(entry)
    case entry.kind
    when :pr then @prs[entry.key]
    when :upstream then @upstream[entry.key]
    else @commits[entry.key]
    end
  end

  def summary(entries)
    counts = Hash.new(0)
    entries.each { |entry| counts[status_for(entry)] += 1 }
    counts
  end
end
