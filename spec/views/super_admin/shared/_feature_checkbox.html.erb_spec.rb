require 'rails_helper'

RSpec.describe 'super_admin/shared/_feature_checkbox', type: :view do
  it 'renders a translated, labelled checkbox with an explanation and an unchecked value' do
    I18n.with_locale(:pt_BR) do
      render partial: 'super_admin/shared/feature_checkbox',
             locals: { feature_key: 'disable_channel_unoapi', display_name: 'Bloquear novas caixas UnoAPI', value: false, disabled: false }
    end
    document = Nokogiri::HTML.fragment(rendered)
    checkbox = document.at_css('input[type="checkbox"]')

    expect(document.at_css("label[for='#{checkbox['id']}']").text).to eq('Bloquear novas caixas UnoAPI')
    expect(checkbox['checked']).to be_nil
    expect(document.at_css('input[type="hidden"]')['value']).to eq('false')
    expect(document.at_css('details').text).to include('já conectadas continuam funcionando')
  end

  it 'does not render a feature name as HTML' do
    render partial: 'super_admin/shared/feature_checkbox',
           locals: { feature_key: 'disable_channel_unoapi', display_name: '<script>alert(1)</script>', value: true, disabled: false }

    document = Nokogiri::HTML.fragment(rendered)
    expect(document.css('script')).to be_empty
    expect(document.at_css('input[type="checkbox"]')['checked']).to eq('checked')
  end
end
