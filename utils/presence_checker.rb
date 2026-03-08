class PresenceChecker
  def self.present?(value)
    return true if value == 0
    return false if value.nil?

    if value.is_a?(Array) || value.is_a?(Hash)
      !value.empty?
    else
      normalized = value.to_s.strip
      !normalized.empty? && normalized != "null" && normalized != "undefined"
    end
  end
end
