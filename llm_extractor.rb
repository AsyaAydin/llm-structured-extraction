require_relative "utils/http_wrapper"
require "json"

class LlmExtractor
  API_URL = "https://api.openai.com/v1/responses"
  MODEL = "gpt-5.2"
  DEFAULT_TIMEOUT = 120

  def initialize(api_key:, prompt_id:, prompt_version:, taxonomy_path: nil)
    raise ArgumentError, "api_key is required" if api_key.to_s.strip.empty?
    raise ArgumentError, "prompt_id is required" if prompt_id.to_s.strip.empty?
    raise ArgumentError, "prompt_version is required" if prompt_version.to_s.strip.empty?

    @api_key = api_key
    @prompt_id = prompt_id
    @prompt_version = prompt_version
    @taxonomy = load_taxonomy(taxonomy_path)
    @taxonomy_json = JSON.generate(@taxonomy)
  end

  def extract_record(input_name:, title:, description:)
    body = build_body(
      input_name: input_name,
      title: title,
      description: description
    )

    code, res = HttpWrapper.post_json(
      API_URL,
      body,
      headers: { "Authorization" => "Bearer #{@api_key}" },
      timeout: DEFAULT_TIMEOUT
    )

    return {} unless code.between?(200, 299)

    parse_response(res.body)
  rescue StandardError => e
    warn "LLM extraction error for #{input_name}: #{e.message}"
    {}
  end

  private

  def load_taxonomy(path)
    return [] if path.nil? || path.strip.empty?
    JSON.parse(File.read(path))
  rescue Errno::ENOENT, JSON::ParserError
    []
  end

  def build_body(input_name:, title:, description:)
    {
      model: MODEL,
      prompt: {
        id: @prompt_id,
        version: @prompt_version,
        variables: {
          "input_name" => input_name,
          "title" => title,
          "description" => description,
          "taxonomy" => @taxonomy_json
        }
      }
    }
  end

  def parse_response(body)
    data = safe_json_parse(body) || {}
    parsed = nil

    (data["output"] || []).each do |item|
      (item["content"] || []).each do |content|
        parsed ||= content["json"] if %w[json output_json].include?(content["type"]) && content["json"].is_a?(Hash)
        parsed ||= safe_json_parse(content["text"]) if %w[text output_text].include?(content["type"])
      end
    end

    parsed ||= safe_json_parse(data["output_text"])
    parsed || {}
  end

  def safe_json_parse(value)
    JSON.parse(value)
  rescue JSON::ParserError, TypeError
    nil
  end
end
