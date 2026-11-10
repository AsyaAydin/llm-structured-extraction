# Validates a parsed JSON value against the small subset of JSON Schema that
# the extraction schemas in this repo use: type (including nullable type lists),
# enum, pattern, properties, required, additionalProperties: false and items.
#
# It is not a general JSON Schema implementation. Keywords outside this subset
# are ignored.
class SchemaValidator
  # Returns a list of human-readable problems; an empty list means valid.
  def self.validate(value, schema, path = "$")
    types = Array(schema["type"])
    unless types.empty? || types.any? { |type| type_matches?(value, type) }
      return ["#{path}: expected #{types.join(" or ")}, got #{type_name(value)}"]
    end

    errors = []

    if schema.key?("enum") && !schema["enum"].include?(value)
      errors << "#{path}: #{value.inspect} is not one of #{schema["enum"].inspect}"
    end

    if value.is_a?(String) && schema["pattern"] && !compile(schema["pattern"]).match?(value)
      errors << "#{path}: #{value.inspect} does not match pattern #{schema["pattern"]}"
    end

    errors.concat(validate_object(value, schema, path)) if value.is_a?(Hash)

    if value.is_a?(Array) && schema["items"]
      value.each_with_index do |item, index|
        errors.concat(validate(item, schema["items"], "#{path}[#{index}]"))
      end
    end

    errors
  end

  def self.validate_object(value, schema, path)
    properties = schema["properties"] || {}
    errors = []

    (schema["required"] || []).each do |key|
      errors << "#{path}.#{key}: missing required property" unless value.key?(key)
    end

    if schema["additionalProperties"] == false
      (value.keys - properties.keys).each do |key|
        errors << "#{path}.#{key}: unexpected property"
      end
    end

    properties.each do |key, subschema|
      errors.concat(validate(value[key], subschema, "#{path}.#{key}")) if value.key?(key)
    end

    errors
  end

  def self.type_matches?(value, type)
    case type
    when "object" then value.is_a?(Hash)
    when "array" then value.is_a?(Array)
    when "string" then value.is_a?(String)
    when "boolean" then value == true || value == false
    when "null" then value.nil?
    when "number" then value.is_a?(Numeric)
    when "integer" then value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.floor)
    else false
    end
  end

  def self.type_name(value)
    case value
    when Hash then "object"
    when Array then "array"
    when String then "string"
    when true, false then "boolean"
    when nil then "null"
    when Numeric then "number"
    else value.class.name
    end
  end

  # JSON Schema anchors match the whole string; Ruby's ^ and $ match per line.
  def self.compile(pattern)
    Regexp.new(pattern.sub(/\A\^/, "\\A").sub(/\$\z/, "\\z"))
  end

  private_class_method :validate_object, :type_matches?, :type_name, :compile
end
