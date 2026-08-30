require 'rails_helper'

# This project replaces Tailwind's palette instead of extending it, so the
# families everybody types from memory — blue, emerald, amber, gray — compile to
# nothing at all. A dead class is invisible in review and invisible in the
# markup: the button is simply there, unstyled, and only somebody opening the
# page notices. That is how the prospect got a transparent "Continuar".
RSpec.describe 'Tailwind palette of the sales screens', type: :view do
  let(:surfaces) do
    ['app/views/sales/**/*.erb',
     'app/javascript/superadmin_pages/views/commercial/*.vue',
     'app/javascript/superadmin_pages/views/financial/*.vue']
  end

  # Mirrors theme/colors.js, which is what tailwind.config.js hands to Tailwind.
  def palette
    @palette ||= begin
      source = Rails.root.join('theme/colors.js').read
      source.scan(/^ {2}([a-z]+): \{(.*?)^ {2}\}/m)
            .to_h
            .transform_values { |body| body.scan(/^ {4}'?(\w+)'?:/).flatten }
    end
  end

  def dead_classes_in(path)
    File.read(path).scan(/[\s"']((?:[a-z-]+:)*(?:bg|text|border|divide|ring)-[a-z][a-z-]*-\d+)/).flatten.uniq.reject do |klass|
      _prefix, family, shade = klass.sub(/\A(?:[a-z-]+:)*/, '').match(/\A(bg|text|border|divide|ring)-(.+)-(\d+)\z/)&.captures
      # `border-b-2` and friends are widths, not colours; `n-*` is the design
      # system's own scale.
      next true if family.nil? || family.length == 1 || family.start_with?('n-')

      palette[family]&.include?(shade)
    end
  end

  it 'reads the palette it is checking against' do
    expect(palette.keys).to include('woot', 'slate', 'green', 'red')
    expect(palette['woot']).to include('25', '500')
  end

  it 'styles every screen with colours that exist' do
    dead = surfaces.flat_map { |glob| Dir[Rails.root.join(glob)] }
                   .to_h { |path| [Pathname(path).relative_path_from(Rails.root).to_s, dead_classes_in(path)] }
                   .reject { |_path, classes| classes.empty? }

    expect(dead).to eq({})
  end
end
