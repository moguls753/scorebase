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
#   :groq     - Groq API (fast, production)
#   :gemini   - Google Gemini API
#   :lmstudio - Local LMStudio server (free, for testing/bulk)
#
class LlmClient
  BACKENDS = %i[groq gemini lmstudio].freeze

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
  class ConfigurationError < Error; end

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
    response = send_request(prompt, json_mode: json_mode, temperature: temperature)
    parse_response(response)
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
    when :lmstudio then send_lmstudio_request(prompt, json_mode: json_mode, temperature: temperature)
    end
  end

  def parse_response(response)
    raise QuotaExceededError, "API quota exceeded" if response.code == "429"

    unless response.code == "200"
      raise Error, "API Error #{response.code}: #{response.body[0..500]}"
    end

    body = JSON.parse(response.body)
    extract_text(body)
  end

  def extract_text(body)
    case @backend
    when :groq, :lmstudio
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
