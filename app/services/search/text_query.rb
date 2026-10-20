# Normalize comparisons only: never rewrite stored content or identity fields.
module Search::TextQuery
  def self.expression(column)
    "regexp_replace(normalize(lower(COALESCE((#{column})::text, '')), NFD), '[̀-ͯ]', '', 'g')"
  end

  def self.normalize(value)
    value.to_s.downcase.unicode_normalize(:nfd).gsub(/[\u0300-\u036f]/, '')
  end

  def self.pattern(value)
    "%#{ActiveRecord::Base.sanitize_sql_like(normalize(value))}%"
  end

  # Columns are internal SQL expressions, never user input. Values stay bound.
  def self.apply(scope, columns, query)
    scope.where(columns.map { |column| "#{expression(column)} LIKE :accent_search" }.join(' OR '), accent_search: pattern(query))
  end
end
