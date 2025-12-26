# Prevent extra checksum headers for S3-compatible backends like R2.
if ENV.fetch('ACTIVE_STORAGE_SERVICE', '') == 's3_compatible' && defined?(Aws)
  Aws.config.update(
    s3: {
      request_checksum_calculation: :never,
      response_checksum_validation: :never
    }
  )
end
