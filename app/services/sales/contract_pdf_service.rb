# Turns a filled contract (HTML) into the PDF sent to Autentique: A4, the
# Auris logo on every page and the page number at the bottom, like the
# original Word model. JavaScript stays off — the HTML carries customer data.
class Sales::ContractPdfService
  LOGO_PATH = Rails.public_path.join('brand-assets/auris_sales_logo.png')
  JS_BREAKING_CHARS = { "\u2028" => '&#x2028;', "\u2029" => '&#x2029;' }.freeze

  def initialize(html)
    @html = html
  end

  def to_pdf
    Grover.new(document.gsub(/[\u2028\u2029]/, JS_BREAKING_CHARS), **options).to_pdf
  end

  private

  def options
    {
      format: 'A4',
      java_script_enabled: false,
      print_background: true,
      display_header_footer: true,
      header_template: header,
      footer_template: '<div style="width:100%;text-align:center;font-size:8px;color:#333">- <span class="pageNumber"></span> -</div>',
      margin: { top: '30mm', bottom: '20mm', left: '18mm', right: '18mm' }
    }
  end

  def header
    logo = Base64.strict_encode64(File.binread(LOGO_PATH))
    %(<div style="width:100%;padding:0 18mm;text-align:right"><img src="data:image/png;base64,#{logo}" style="height:28px"></div>)
  end

  def document
    <<~HTML
      <!doctype html>
      <html lang="pt-BR"><head><meta charset="utf-8">
      <style>
        body { font-family: Arial, Helvetica, sans-serif; font-size: 10.5pt; line-height: 1.45; color: #111; }
        h2 { font-size: 12pt; margin: 0 0 6px; } h3 { font-size: 11pt; margin: 0 0 12px; }
        p { margin: 0 0 6px; text-align: justify; }
        table { width: 100%; border-collapse: collapse; margin: 0 0 14px; }
        td, th { border: 1px solid #111; padding: 6px 8px; vertical-align: middle; text-align: left; }
        td:first-child { width: 28%; }
        ul { margin: 0; padding-left: 18px; }
        a { color: #1d4ed8; }
      </style></head>
      <body>#{@html}</body></html>
    HTML
  end
end
