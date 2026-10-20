class EnableUnaccentForArticleSearch < ActiveRecord::Migration[7.1]
  def up
    enable_extension 'unaccent' unless extension_enabled?('unaccent')
  end

  # Shared PostgreSQL extension: rolling back this feature must not drop it.
  def down; end
end
