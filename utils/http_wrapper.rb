require "json"
require "net/http"
require "openssl"
require "uri"

# Minimal JSON-over-HTTP client on top of Net::HTTP.
class HttpWrapper
  DEFAULT_TIMEOUT = 15

  NETWORK_ERRORS = [
    Timeout::Error,
    SocketError,
    OpenSSL::SSL::SSLError,
    SystemCallError,
    EOFError
  ].freeze

  # Returns [status_code, body]. A request that never got an HTTP response
  # (DNS failure, timeout, refused connection) returns [0, "ErrorClass: message"],
  # so callers can report why it failed instead of treating it as an empty result.
  def self.post_json(url, body_hash, headers: {}, timeout: DEFAULT_TIMEOUT)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = timeout
    http.read_timeout = timeout

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    headers.each { |name, value| request[name] = value }
    request.body = JSON.generate(body_hash)

    response = http.request(request)
    [response.code.to_i, response.body.to_s.force_encoding("UTF-8")]
  rescue *NETWORK_ERRORS => e
    [0, "#{e.class}: #{e.message}"]
  end
end
