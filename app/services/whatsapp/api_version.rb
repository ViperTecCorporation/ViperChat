class Whatsapp::ApiVersion
  DEFAULT = 'v26.0'.freeze

  def self.current
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', DEFAULT)
    raise ArgumentError, 'WHATSAPP_API_VERSION must match v<number>.0' unless version.is_a?(String) && /\Av\d+\.0\z/.match?(version)

    version
  end
end
