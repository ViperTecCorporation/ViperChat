# Define an application-wide HTTP permissions policy. For further
# information see https://developers.google.com/web/updates/2018/06/feature-policy
#
Rails.application.config.permissions_policy do |f|
  # Allow WebRTC voice to request microphone access from same origin.
  f.microphone :self
end
