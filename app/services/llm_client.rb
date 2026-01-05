# frozen_string_literal: true

require "net/http"
require "json"

# Unified LLM client with support for multiple backends.
#
# Usage:
#   client = LlmClient.new(backend: :groq)
#   response = client.chat("What is 2+2?")
#   # => "4"
#
#   # With JSON mode (for structured responses)
#   response = client.chat("Return JSON: {answer: 4}", json_mode: true)
#
# Backends:
#   :groq     - Groq API (llama-3.1-8b) - DEFAULT, cheapest
#   :openai   - OpenAI API (gpt-4o-mini) - best quality for complex tasks
#   :gemini   - Google Gemini API
#   :lmstudio - Local LMStudio server (free, for testing/bulk)
#
class LlmClient
  BACKENDS = %i[groq gemini openai lmstudio].freeze

  # SSL certificate store for HTTPS requests
  # OpenSSL 3.6+ requires explicit configuration to work with modern APIs
  # that don't provide CRL (Certificate Revocation List) endpoints
  SSL_CERT_STORE = begin
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    store
  end.freeze

  class Error < StandardError; end
  class QuotaExceededError < Error; end
  class RateLimitError < Error; end
  class ConfigurationError < Error; end

  # Retry configuration for rate limits
  MAX_RETRIES = 5
  BASE_DELAY = 2.0 # seconds

  # Default backend from ENV or config
  def self.default_backend
    ENV.fetch("LLM_BACKEND", "groq").to_sym
  end

  def initialize(backend: nil, model: nil)
    @backend = backend || self.class.default_backend
    @model = model

    raise ConfigurationError, "Unknown backend: #{@backend}" unless BACKENDS.include?(@backend)

    validate_configuration!
  end

  attr_reader :backend

  # Send a chat prompt and return the response text
  #
  # @param prompt [String] The prompt to send
  # @param json_mode [Boolean] Whether to request JSON response format
  # @param temperature [Float] Temperature for response generation (0.0-1.0)
  # @return [String] The response text
  def chat(prompt, json_mode: false, temperature: 0.1)
    retries = 0
    begin
      response = send_request(prompt, json_mode: json_mode, temperature: temperature)
      parse_response(response)
    rescue RateLimitError
      retries += 1
      raise QuotaExceededError, "Rate limit exceeded after #{MAX_RETRIES} retries" if retries > MAX_RETRIES

      delay = BASE_DELAY * (2**(retries - 1)) + rand(0.0..1.0) # 2s, 4s, 8s, 16s, 32s
      Rails.logger.warn "[LlmClient] Rate limited, retry #{retries}/#{MAX_RETRIES} after #{delay.round(1)}s"
      sleep(delay)
      retry
    end
  end

  # Convenience method for JSON responses - parses the result
  #
  # @param prompt [String] The prompt to send (should ask for JSON)
  # @param temperature [Float] Temperature for response generation
  # @return [Hash, Array] The parsed JSON response
  def chat_json(prompt, temperature: 0.1)
    text = chat(prompt, json_mode: true, temperature: temperature)
    # Strip markdown code fences if present
    text = text.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "").strip
    JSON.parse(text)
  end

  private

  def validate_configuration!
    case @backend
    when :groq
      api_key = Rails.application.credentials.dig(:groq, :api_key)
      raise ConfigurationError, "Groq API key not set in Rails credentials" if api_key.blank?
    when :gemini
      api_key = Rails.application.credentials.dig(:gemini, :api_key)
      raise ConfigurationError, "Gemini API key not set in Rails credentials" if api_key.blank?
    when :openai
      api_key = Rails.application.credentials.dig(:openai, :api_key)
      raise ConfigurationError, "OpenAI API key not set in Rails credentials" if api_key.blank?
    when :lmstudio
      # LMStudio runs locally, no API key needed
      # Just verify the server URL is configured
      server_url = lmstudio_url
      raise ConfigurationError, "LMStudio server URL not configured" if server_url.blank?
    end
  end

  def send_request(prompt, json_mode:, temperature:)
    case @backend
    when :groq    then send_groq_request(prompt, json_mode: json_mode, temperature: temperature)
    when :gemini  then send_gemini_request(prompt, json_mode: json_mode, temperature: temperature)
    when :openai  then send_openai_request(prompt, json_mode: json_mode, temperature: temperature)
    when :lmstudio then send_lmstudio_request(prompt, json_mode: json_mode, temperature: temperature)
    end
  end

  def parse_response(response)
    if response.code == "429"
      # Parse error body to distinguish rate limit from billing quota
      error_body = JSON.parse(response.body) rescue {}
      error_type = error_body.dig("error", "type") || ""
      error_msg = error_body.dig("error", "message") || "Rate limited"

      # Billing quota exceeded is not retryable
      if error_type.include?("insufficient_quota") || error_msg.include?("exceeded your current quota")
        raise QuotaExceededError, "Billing quota exceeded: #{error_msg}"
      else
        raise RateLimitError, error_msg
      end
    end

    unless response.code == "200"
      raise Error, "API Error #{response.code}: #{response.body[0..500]}"
    end

    body = JSON.parse(response.body)
    extract_text(body)
  end

  def extract_text(body)
    case @backend
    when :groq, :openai, :lmstudio
      body.dig("choices", 0, "message", "content") || raise(Error, "No content in response")
    when :gemini
      body.dig("candidates", 0, "content", "parts", 0, "text") || raise(Error, "No content in response")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Groq
  # ═══════════════════════════════════════════════════════════════════════════

  GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
  GROQ_DEFAULT_MODEL = "llama-3.1-8b-instant"

  def send_groq_request(prompt, json_mode:, temperature:)
    uri = URI(GROQ_ENDPOINT)
    api_key = Rails.application.credentials.dig(:groq, :api_key)

    payload = {
      model: @model || ENV.fetch("GROQ_MODEL", GROQ_DEFAULT_MODEL),
      temperature: temperature,
      messages: [{ role: "user", content: prompt }]
    }
    payload[:response_format] = { type: "json_object" } if json_mode

    http_post(uri, payload, { "Authorization" => "Bearer #{api_key}" })
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Gemini
  # ═══════════════════════════════════════════════════════════════════════════

  GEMINI_DEFAULT_MODEL = "gemini-2.0-flash-lite"

  def send_gemini_request(prompt, json_mode:, temperature:)
    model = @model || ENV.fetch("GEMINI_MODEL", GEMINI_DEFAULT_MODEL)
    api_key = Rails.application.credentials.dig(:gemini, :api_key)
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}")

    generation_config = { temperature: temperature }
    generation_config[:responseMimeType] = "application/json" if json_mode

    payload = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: generation_config
    }

    http_post(uri, payload)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # OpenAI
  # ═══════════════════════════════════════════════════════════════════════════

  OPENAI_ENDPOINT = "https://api.openai.com/v1/chat/completions"
  OPENAI_DEFAULT_MODEL = "gpt-4.1-mini"

  # Models that don't support custom temperature (only default 1.0)
  OPENAI_NO_TEMPERATURE_MODELS = %w[
    gpt-5-nano gpt-5-nano-2025-08-07
    gpt-5-mini gpt-5-mini-2025-08-07
  ].freeze

  def send_openai_request(prompt, json_mode:, temperature:)
    uri = URI(OPENAI_ENDPOINT)
    api_key = Rails.application.credentials.dig(:openai, :api_key)
    model = @model || ENV.fetch("OPENAI_MODEL", OPENAI_DEFAULT_MODEL)

    payload = {
      model: model,
      messages: [{ role: "user", content: prompt }]
    }
    # Some models (gpt-5-nano) don't support custom temperature
    payload[:temperature] = temperature unless OPENAI_NO_TEMPERATURE_MODELS.include?(model)
    payload[:response_format] = { type: "json_object" } if json_mode

    http_post(uri, payload, { "Authorization" => "Bearer #{api_key}" })
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LMStudio (local)
  # ═══════════════════════════════════════════════════════════════════════════

  LMSTUDIO_DEFAULT_URL = "http://localhost:1234/v1/chat/completions"
  LMSTUDIO_DEFAULT_MODEL = "qwen2.5-7b-instruct"

  def lmstudio_url
    ENV.fetch("LMSTUDIO_URL", LMSTUDIO_DEFAULT_URL)
  end

  def send_lmstudio_request(prompt, json_mode:, temperature:)
    uri = URI(lmstudio_url)

    payload = {
      model: @model || ENV.fetch("LMSTUDIO_MODEL", LMSTUDIO_DEFAULT_MODEL),
      temperature: temperature,
      messages: [{ role: "user", content: prompt }]
    }
    # LMStudio uses OpenAI-compatible API
    payload[:response_format] = { type: "json_object" } if json_mode

    http_post(uri, payload, use_ssl: false)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HTTP Helper
  # ═══════════════════════════════════════════════════════════════════════════

  def http_post(uri, payload, headers = {}, use_ssl: true)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = use_ssl && uri.scheme == "https"
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.cert_store = SSL_CERT_STORE
    end
    http.read_timeout = 120

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    headers.each { |k, v| req[k] = v }
    req.body = payload.to_json

    http.request(req)
  end
end
