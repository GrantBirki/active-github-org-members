# frozen_string_literal: true

require "open3"
require "uri"

class SecretResolver
  class OnePassword
    def read(reference)
      stdout, stderr, status = Open3.capture3("op", "read", reference)
      unless status.success?
        message = stderr.strip
        message = "op read failed" if message.empty?
        raise "Unable to read secret from 1Password: #{message}"
      end

      raise "Secret from 1Password is empty" if stdout.strip.empty?

      stdout
    end
  end

  PROVIDERS = {
    "op" => OnePassword.new,
  }.freeze

  def self.supported_reference?(value)
    PROVIDERS.key?(scheme(value))
  end

  def self.read(reference)
    provider = PROVIDERS[scheme(reference)]
    raise "Unsupported secret reference" unless provider

    provider.read(reference)
  end

  def self.scheme(value)
    URI.parse(value.to_s).scheme
  rescue URI::InvalidURIError
    nil
  end
  private_class_method :scheme
end
