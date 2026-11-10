require "minitest/autorun"
require "json"

ROOT = File.expand_path("..", __dir__)
FIXTURES = File.join(__dir__, "fixtures")

# Builds a Responses API body whose message contains the given content parts.
def api_response(*parts, status: "completed", **extra)
  JSON.generate({ status: status, output: [{ type: "reasoning" }, { type: "message", content: parts }] }.merge(extra))
end

def output_text(text)
  { type: "output_text", text: text }
end

# Transport double: returns a canned [status, body] and remembers the request.
class FakeTransport
  attr_reader :requests

  def initialize(status, body)
    @status = status
    @body = body
    @requests = []
  end

  def call(record_id, body)
    @requests << [record_id, body]
    [@status, @body]
  end
end
