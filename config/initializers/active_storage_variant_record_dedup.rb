# Handles concurrent creation of the same ActiveStorage variant.
# When two processes try to insert the same (blob_id, variation_digest),
# Postgres raises a unique constraint error. We retry by looking up the
# existing record instead of bubbling the exception.
ActiveSupport.on_load(:active_storage) do
  module ActiveStorageVariantRecordDedup
    def find_or_create_by_blob_and_variation(blob, variation)
      super
    rescue ActiveRecord::RecordNotUnique
      find_by(blob: blob, variation_digest: variation.digest)
    end
  end

  ActiveStorage::VariantRecord.singleton_class.prepend(ActiveStorageVariantRecordDedup)
end
