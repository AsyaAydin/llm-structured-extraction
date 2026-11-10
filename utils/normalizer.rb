# Turns an HTML fragment into plain text for the model.
class Normalizer
  # Tags that end a line of text; every other tag is replaced by a space.
  BLOCK_TAGS = %r{</?(?:p|div|br|li|ul|ol|tr|table|h[1-6]|section|article|header|footer|blockquote)\b[^>]*>}i

  NAMED_ENTITIES = {
    "nbsp" => " ", "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'",
    "euro" => "€", "pound" => "£", "ndash" => "–", "mdash" => "—", "middot" => "·", "bull" => "•"
  }.freeze

  def self.strip_html(text)
    return "" if text.nil?

    text.to_s
        .gsub(/\r\n?/, "\n")
        .gsub(%r{<(script|style)\b.*?</\1\s*>}mi, " ")
        .gsub(/<!--.*?-->/m, " ")
        .gsub(BLOCK_TAGS, "\n")
        .gsub(%r{</?[a-zA-Z][^>]*>}, " ")
        .then { |stripped| decode_entities(stripped) }
        .gsub(/[ \t\f\v ]+/, " ")
        .gsub(/ ?\n[ \n]*/, "\n")
        .strip
  end

  # Decodes numeric entities and the common named ones in a single pass, so
  # "&amp;lt;" becomes "&lt;" and not "<". Unknown named entities are left as is.
  def self.decode_entities(text)
    text.gsub(/&(#[0-9]+|#x\h+|[a-zA-Z]+);/) do |match|
      entity = Regexp.last_match(1)
      if entity.start_with?("#x", "#X")
        codepoint_to_s(entity[2..].to_i(16)) || match
      elsif entity.start_with?("#")
        codepoint_to_s(entity[1..].to_i) || match
      else
        NAMED_ENTITIES.fetch(entity, match)
      end
    end
  end

  def self.codepoint_to_s(codepoint)
    char = [codepoint].pack("U")
    char.valid_encoding? ? char : nil
  rescue RangeError
    nil
  end

  private_class_method :codepoint_to_s
end
