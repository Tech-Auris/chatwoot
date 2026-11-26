# Backport of the Rails 8.0.5.2 fix for GHSA-8474-xrp6-wh69 (rails/rails@210ac22), which has no
# 7.1 release. Remove once on a Rails release that includes it. Ported from fazer-ai/chatwoot#931.
#
# On a LoadError, `safe_constantize` built a regular expression from the requested name without
# escaping it. Action Cable passes the `channel` of every `subscribe` command to it before any
# lookup, so a client of /cable chooses the input. The fix matches the first segment of the name
# as a literal string instead.
module ActiveSupportSafeConstantizeLiteralMatch
  # Rails' own method with only the LoadError check changed, kept line for line so the diff
  # against activesupport 7.1.5.2 stays readable.
  def safe_constantize(camel_cased_word) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    constantize(camel_cased_word)
  rescue NameError => e
    raise if e.name && !(camel_cased_word.to_s.split('::').include?(e.name.to_s) ||
      e.name.to_s == camel_cased_word.to_s)
  rescue LoadError => e
    message = e.respond_to?(:original_message) ? e.original_message : e.message
    constant_name = camel_cased_word.split('::').find { |part| !part.empty? } || camel_cased_word
    raise unless message.include?("Unable to autoload constant #{constant_name}")
  end
end

ActiveSupport::Inflector.singleton_class.prepend(ActiveSupportSafeConstantizeLiteralMatch) unless
  ActiveSupport::Inflector.singleton_class < ActiveSupportSafeConstantizeLiteralMatch
