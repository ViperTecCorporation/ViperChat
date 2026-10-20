# Extends the caller's authorized scope, without changing stored names or IDs.
class Search::GroupNameFilterService
  pattr_initialize [:scope!, :query!]

  def perform
    terms = Search::TextQuery.normalize(query).split.uniq
    return scope.none if terms.empty?

    title = Search::TextQuery.expression("COALESCE(NULLIF(conversations.group_title, ''), contacts.name, '')")
    terms.reduce(scope.where(group: true)) do |matches, term|
      matches.where("#{title} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end
  end
end
