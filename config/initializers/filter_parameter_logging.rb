# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes, :provider_config,
  :call # VoIP snapshots contain caller identity and must never be logged in full.
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]

# Some initializers load Active Record before this file. Apply the final filters
# to SQL bind logging too, including credential-bearing JSON columns.
ActiveSupport.on_load(:active_record) do
  self.filter_attributes |= Rails.application.config.filter_parameters
end
