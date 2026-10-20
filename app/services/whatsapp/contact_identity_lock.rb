# Shared by live and historical contact creation. Transaction-scoped PostgreSQL
# locks serialize only the same account/comparison phone, including BR 8/9 aliases.
class Whatsapp::ContactIdentityLock
  def self.synchronize(account_id:, phone:, &)
    normalized = Whatsapp::InboxLinkPhoneService.normalize(phone)
    return yield unless normalized

    ActiveRecord::Base.transaction do
      connection = ActiveRecord::Base.connection
      key = connection.quote("whatsapp-contact:#{Integer(account_id)}:#{normalized}")
      connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{key}, 0))")
      # A query cached before waiting must not hide the competing creator's commit.
      ActiveRecord::Base.uncached(&)
    end
  end

  def self.phone_variants(phone)
    normalized = Whatsapp::InboxLinkPhoneService.normalize(phone)
    return [] unless normalized

    variants = [normalized, phone.to_s.delete_prefix('+')]
    variants << normalized.sub(/\A(55\d{2})9/, '\1') if normalized.match?(/\A55\d{2}9[6-9]\d{7}\z/)
    variants.uniq
  end
end
