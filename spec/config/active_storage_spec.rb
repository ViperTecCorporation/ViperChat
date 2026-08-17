require 'rails_helper'

RSpec.describe ActiveStorage do
  it 'serves Apple-compatible video attachments inline' do
    expect(Rails.application.config.active_storage.content_types_allowed_inline).to include(
      'video/mp4',
      'video/quicktime',
      'video/x-m4v'
    )
  end
end
