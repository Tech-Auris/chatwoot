require 'administrate/field/base'

# Renders a text attribute stored as HTML (Quill-composed rich content on
# the OperationsNotification form). The show partial renders the HTML
# directly (already sanitized by the model on write); the index partial
# strips the markup so a row preview stays a single line of plain text.
class HtmlTextField < Administrate::Field::Base
  # Turns the stored HTML into a compact plain-text preview: strips tags,
  # collapses whitespace, and truncates. Used by the index partial and
  # the search snippet.
  def preview_text(limit: 120)
    ActionController::Base.helpers.strip_tags(data.to_s)
                          .gsub(/\s+/, ' ')
                          .strip
                          .then { |text| limit ? text.truncate(limit) : text }
  end

  def html
    data.to_s
  end
end
