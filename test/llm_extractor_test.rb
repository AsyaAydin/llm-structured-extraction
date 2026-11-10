require_relative "test_helper"
require_relative "../llm_extractor"

class LlmExtractorTest < Minitest::Test
  SCHEMA = JSON.parse(File.read(File.join(ROOT, "schema", "event.schema.json")))
  VALID = {
    "event_type" => "meetup", "start_date" => "2026-03-12", "start_time" => "19:00",
    "format" => "in_person", "city" => "Istanbul", "is_free" => true,
    "price_amount" => nil, "price_currency" => nil, "topic" => "software_engineering"
  }.freeze

  def extract(status, body)
    transport = FakeTransport.new(status, body)
    extractor = LlmExtractor.new(transport: transport, instructions: "Extract.", schema: SCHEMA, schema_name: "event")
    [extractor.extract(record_id: "r1", input: "some text"), transport]
  end

  def test_valid_output_is_ok
    result, = extract(200, api_response(output_text(JSON.generate(VALID))))
    assert result.ok?
    assert_equal VALID, result.data
    assert_nil result.error
  end

  def test_request_carries_prompt_input_and_strict_schema
    _, transport = extract(200, api_response(output_text(JSON.generate(VALID))))
    record_id, body = transport.requests.first
    assert_equal "r1", record_id
    assert_equal "gpt-5.2", body[:model]
    assert_equal "Extract.", body[:instructions]
    assert_equal "some text", body[:input]
    assert_equal({ type: "json_schema", name: "event", strict: true, schema: SCHEMA }, body[:text][:format])
  end

  def test_output_split_over_several_parts_is_joined
    json = JSON.generate(VALID)
    result, = extract(200, api_response(output_text(json[0, 20]), output_text(json[20..])))
    assert result.ok?
  end

  def test_prose_is_invalid_json
    result, = extract(200, api_response(output_text("Sure! Here is the result")))
    assert_equal "invalid_json", result.status
    assert_nil result.data
  end

  def test_truncated_json_is_invalid_json
    result, = extract(200, api_response(output_text('{"event_type":"mee')))
    assert_equal "invalid_json", result.status
  end

  def test_wrong_shape_is_invalid_schema
    result, = extract(200, api_response(output_text('{"level":42,"unexpected":null}')))
    assert_equal "invalid_schema", result.status
    assert_includes result.error, "$.event_type: missing required property"
    assert_includes result.error, "$.level: unexpected property"
    assert_nil result.data
  end

  def test_json_array_is_invalid_schema
    result, = extract(200, api_response(output_text("[1,2]")))
    assert_equal "invalid_schema", result.status
  end

  def test_wrong_value_format_is_invalid_schema
    result, = extract(200, api_response(output_text(JSON.generate(VALID.merge("start_date" => "March 12")))))
    assert_equal "invalid_schema", result.status
    assert_includes result.error, "$.start_date"
  end

  def test_refusal
    result, = extract(200, api_response({ type: "refusal", refusal: "I can't help with that." }))
    assert_equal "refused", result.status
    assert_equal "I can't help with that.", result.error
  end

  def test_incomplete_response
    body = api_response(output_text('{"event_type":"mee'), status: "incomplete", incomplete_details: { reason: "max_output_tokens" })
    result, = extract(200, body)
    assert_equal "incomplete", result.status
    assert_includes result.error, "max_output_tokens"
  end

  def test_response_without_output_text
    result, = extract(200, JSON.generate(status: "completed", output: []))
    assert_equal "invalid_json", result.status
  end

  def test_non_json_api_response
    result, = extract(200, "<html>gateway</html>")
    assert_equal "invalid_response", result.status
  end

  def test_http_errors_report_status_and_api_message
    result, = extract(401, '{"error":{"message":"Incorrect API key provided"}}')
    assert_equal "api_error", result.status
    assert_equal "HTTP 401: Incorrect API key provided", result.error

    result, = extract(429, '{"error":{"message":"Rate limit reached"}}')
    assert_equal "HTTP 429: Rate limit reached", result.error

    result, = extract(500, "oops")
    assert_equal "HTTP 500: oops", result.error
  end

  def test_network_failure
    result, = extract(0, "SocketError: getaddrinfo failed")
    assert_equal "api_error", result.status
    assert_equal "request failed: SocketError: getaddrinfo failed", result.error
  end
end
