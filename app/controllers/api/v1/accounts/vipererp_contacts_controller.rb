# Bounded replication contract. The regular contacts API remains unchanged.
class Api::V1::Accounts::VipererpContactsController < Api::V1::Accounts::ContactsController
  def changes
    window = replication_window
    rows = Current.account.contacts.where('(updated_at, id) > (?, ?) AND updated_at < ?',
                                          Time.at(Rational(window[:since], 1_000_000)).utc, window[:after_id],
                                          Time.at(Rational(window[:cutoff], 1_000_000)).utc)
                  .order(:updated_at, :id).limit(window[:limit] + 1).select(:id, :name, :phone_number, :updated_at).to_a
    render json: replication_page(rows, window)
  rescue ArgumentError, TypeError
    render json: { error: 'Invalid replication cursor' }, status: :unprocessable_entity
  end

  def show
    render json: { payload: replication_payload(@contact) }
  end

  def update
    expected = params.require(:expected_version)
    attributes = params.permit(:name, :phone_number).to_h
    return render json: { error: 'Invalid replication fields' }, status: :unprocessable_entity unless valid_replication_fields?(attributes)

    @contact.with_lock do
      unless expected == version(@contact)
        render json: { error: 'Contact changed concurrently' }, status: :conflict
        next
      end

      @contact.assign_attributes(attributes)
      sync_whatsapp_contact_inbox_source_ids
      @contact.save!
    end
    return if performed?

    render json: { payload: replication_payload(@contact) }
  end

  private

  def replication_window
    ceiling = (Time.current.to_i - 5) * 1_000_000
    window = { since: integer_param(:since, 0), after_id: integer_param(:after_id, 0),
               cutoff: integer_param(:until, ceiling), limit: integer_param(:limit, 100) }
    raise ArgumentError if window[:since].negative? || window[:after_id].negative? ||
                           !window[:cutoff].between?(window[:since], ceiling) || !window[:limit].between?(1, 100)

    window
  end

  def replication_page(rows, window)
    page = rows.first(window[:limit])
    last = page.last
    { payload: page.map { |contact| replication_payload(contact) },
      meta: { until: window[:cutoff], has_more: rows.length > window[:limit],
              cursor_time: last ? micros(last.updated_at) : window[:since], cursor_id: last ? last.id : window[:after_id] } }
  end

  def valid_replication_fields?(attributes)
    phone = attributes['phone_number']
    attributes.keys.sort == %w[name phone_number] && attributes['name'].is_a?(String) && attributes['name'].length <= 150 &&
      phone.is_a?(String) && phone.match?(/\A\+[1-9][0-9]{7,14}\z/) && Phonelib.valid?(phone)
  end

  # Replication sees the account directory, so it requires an account administrator.
  # The inherited token, membership, API feature and per-record guards still apply.
  def check_authorization(_model = nil)
    check_admin_authorization?
  end

  def integer_param(key, fallback)
    params[key].nil? ? fallback : Integer(params[key], 10)
  end

  def micros(time)
    (time.to_r * 1_000_000).to_i
  end

  def version(contact)
    Digest::SHA256.hexdigest([contact.id, micros(contact.updated_at), contact.name, contact.phone_number].to_json)
  end

  def replication_payload(contact)
    { id: contact.id, name: contact.name, phone_number: contact.phone_number, modified: micros(contact.updated_at), version: version(contact) }
  end
end
