require "fileutils"
require "json"

require_relative "http_wrapper"

# A transport takes (record_id, request_body) and returns [http_status, response_body].
#
# Hiding the API call behind this one method lets the same extraction code run
# against the live API, save what the API returned, or replay saved responses
# offline without an API key.
module Transport
  def self.path_for(dir, record_id)
    File.join(dir, "#{record_id.to_s.gsub(/[^A-Za-z0-9_.-]/, "_")}.json")
  end

  # Calls the OpenAI Responses API.
  class Live
    API_URL = "https://api.openai.com/v1/responses"
    TIMEOUT = 120

    def initialize(api_key:, http: HttpWrapper)
      @api_key = api_key
      @http = http
    end

    def call(_record_id, body)
      @http.post_json(
        API_URL,
        body,
        headers: { "Authorization" => "Bearer #{@api_key}" },
        timeout: TIMEOUT
      )
    end
  end

  # Wraps another transport and saves every response as DIR/<record_id>.json.
  class Recording
    def initialize(inner, dir)
      @inner = inner
      @dir = dir
      FileUtils.mkdir_p(dir)
    end

    def call(record_id, body)
      status, response = @inner.call(record_id, body)
      saved = { "http_status" => status, "body" => parse_or_keep(response) }
      File.write(Transport.path_for(@dir, record_id), JSON.pretty_generate(saved) + "\n")
      [status, response]
    end

    private

    def parse_or_keep(response)
      JSON.parse(response)
    rescue JSON::ParserError, TypeError
      response
    end
  end

  # Reads responses saved by Recording instead of calling the API.
  class Replay
    def initialize(dir)
      @dir = dir
    end

    def call(record_id, _body)
      path = Transport.path_for(@dir, record_id)
      return [0, "no recorded response at #{path}"] unless File.exist?(path)

      saved = JSON.parse(File.read(path))
      body = saved["body"]
      [saved["http_status"].to_i, body.is_a?(String) ? body : JSON.generate(body)]
    rescue JSON::ParserError => e
      [0, "recorded response at #{path} is not valid JSON: #{e.message}"]
    end
  end
end
