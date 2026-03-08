require "json"
require "uri"
require "net/http"
require "openssl"

class HttpWrapper
  DEFAULT_TIMEOUT = 15
  MAX_REDIRECTS   = 3

  def self.get(url, headers: {}, timeout: DEFAULT_TIMEOUT, follow: MAX_REDIRECTS)
    request(:get, url, nil, headers, timeout, follow)
  end

  def self.post_json(url, body_hash, headers: {}, timeout: DEFAULT_TIMEOUT)
    request(
      :post,
      url,
      JSON.dump(body_hash),
      headers.merge("Content-Type" => "application/json"),
      timeout
    )
  end

  private

  def self.request(method, url, body = nil, headers = {}, timeout = DEFAULT_TIMEOUT, follow = MAX_REDIRECTS)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = timeout
    http.read_timeout = timeout

    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    headers.each { |k, v| req[k] = v }
    req.body = body if body

    res = http.request(req)

    if res.is_a?(Net::HTTPRedirection) && follow > 0
      location = res["location"]
      new_url = URI.join(url, location).to_s rescue location
      return request(method, new_url, body, headers, timeout, follow - 1)
    end

    [res.code.to_i, res]
  rescue Timeout::Error, SocketError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED => e
    warn "[HTTP #{method.upcase}] #{url} failed: #{e.class} - #{e.message}"
    [0, nil]
  end
end
