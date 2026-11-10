require "json"

require_relative "utils/schema_validator"

# Sends one text to the model with a JSON Schema and returns either the
# validated object or the reason it could not be produced.
#
# Statuses:
#   ok               model output parsed and matches the schema
#   api_error        no usable HTTP response (network failure or non-2xx status)
#   invalid_response the API response itself was not the expected JSON
#   incomplete       the model stopped before finishing its output
#   refused          the model declined to answer
#   invalid_json     the model's output text is not JSON
#   invalid_schema   the output is JSON but does not match the schema
class LlmExtractor
  DEFAULT_MODEL = "gpt-5.2"

  Result = Struct.new(:status, :data, :error, keyword_init: true) do
    def ok?
      status == "ok"
    end
  end

  def initialize(transport:, instructions:, schema:, schema_name:, model: DEFAULT_MODEL)
    raise ArgumentError, "instructions are required" if instructions.to_s.strip.empty?
    raise ArgumentError, "schema must be a JSON object" unless schema.is_a?(Hash)

    @transport = transport
    @instructions = instructions
    @schema = schema
    @schema_name = schema_name
    @model = model
  end

  def extract(record_id:, input:)
    status, body = @transport.call(record_id, build_body(input))

    return failure("api_error", "request failed: #{body}") if status.zero?
    return failure("api_error", "HTTP #{status}: #{api_error_message(body)}") unless status.between?(200, 299)

    interpret(body)
  end

  # Request body for the OpenAI Responses API. The prompt and the schema both
  # come from files in this repo; strict mode asks the API to constrain the
  # model's output to the schema.
  def build_body(input)
    {
      model: @model,
      instructions: @instructions,
      input: input,
      text: {
        format: {
          type: "json_schema",
          name: @schema_name,
          strict: true,
          schema: @schema
        }
      },
      store: false
    }
  end

  private

  def interpret(body)
    response = parse_json(body)
    return failure("invalid_response", "API response is not a JSON object") unless response.is_a?(Hash)

    if response["status"] == "incomplete"
      reason = response.dig("incomplete_details", "reason") || "unknown reason"
      return failure("incomplete", "model output was cut off (#{reason})")
    end

    parts = content_parts(response)
    refusal = parts.find { |part| part["type"] == "refusal" }
    return failure("refused", refusal["refusal"].to_s) if refusal

    text = parts.select { |part| part["type"] == "output_text" }.map { |part| part["text"].to_s }.join
    return failure("invalid_json", "response contains no output text") if text.strip.empty?

    data = parse_json(text)
    return failure("invalid_json", "model output is not valid JSON") if data.nil?

    errors = SchemaValidator.validate(data, @schema)
    return failure("invalid_schema", errors.join("; ")) unless errors.empty?

    Result.new(status: "ok", data: data)
  end

  def content_parts(response)
    output = response["output"]
    return [] unless output.is_a?(Array)

    output.flat_map do |item|
      item.is_a?(Hash) && item["content"].is_a?(Array) ? item["content"] : []
    end.select { |part| part.is_a?(Hash) }
  end

  def api_error_message(body)
    parsed = parse_json(body)
    message = parsed.dig("error", "message") if parsed.is_a?(Hash) && parsed["error"].is_a?(Hash)
    (message || body).to_s.strip[0, 300]
  end

  def parse_json(value)
    JSON.parse(value)
  rescue JSON::ParserError, TypeError
    nil
  end

  def failure(status, error)
    Result.new(status: status, error: error)
  end
end
