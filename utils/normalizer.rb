require "uri"

class Normalizer
  def self.normalize_url(url)
    return nil if url.nil?

    value = url.strip
    return nil if value.empty? || value.match?(/^(mailto:|tel:|javascript:)/i)

    value = "https://#{value}" unless value.match?(/^[a-z]+:\/\//i)
    uri = URI(value)

    uri.host&.downcase&.sub(/^www\./, "")
  rescue URI::InvalidURIError
    nil
  end

  def self.strip_html(text)
    return "" if text.nil?

    text
      .gsub(/<script.*?>.*?<\/script>/mi, " ")
      .gsub(/<style.*?>.*?<\/style>/mi, " ")
      .gsub(/<[^>]+>/, " ")
      .gsub(/\s+/, " ")
      .strip
  end
end
