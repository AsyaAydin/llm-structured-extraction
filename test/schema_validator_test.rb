require_relative "test_helper"
require_relative "../utils/schema_validator"

class SchemaValidatorTest < Minitest::Test
  SCHEMA = JSON.parse(File.read(File.join(ROOT, "schema", "event.schema.json")))

  def valid_event
    {
      "event_type" => "meetup", "start_date" => "2026-03-12", "start_time" => "19:00",
      "format" => "in_person", "city" => "Istanbul", "is_free" => true,
      "price_amount" => nil, "price_currency" => nil, "topic" => "software_engineering"
    }
  end

  def errors_for(overrides)
    SchemaValidator.validate(valid_event.merge(overrides), SCHEMA)
  end

  def test_accepts_a_valid_event
    assert_empty SchemaValidator.validate(valid_event, SCHEMA)
  end

  def test_accepts_null_for_nullable_fields
    assert_empty errors_for("start_date" => nil, "start_time" => nil, "city" => nil, "is_free" => nil)
  end

  def test_accepts_integer_and_float_prices
    assert_empty errors_for("price_amount" => 349, "price_currency" => "EUR")
    assert_empty errors_for("price_amount" => 12.5, "price_currency" => "EUR")
  end

  def test_rejects_missing_property
    event = valid_event
    event.delete("topic")
    assert_equal ["$.topic: missing required property"], SchemaValidator.validate(event, SCHEMA)
  end

  def test_rejects_unexpected_property
    assert_equal ["$.organiser: unexpected property"], errors_for("organiser" => "x")
  end

  def test_rejects_wrong_type
    assert_equal ["$.price_amount: expected number or null, got string"], errors_for("price_amount" => "349")
    assert_equal ["$.is_free: expected boolean or null, got string"], errors_for("is_free" => "yes")
  end

  def test_rejects_null_for_non_nullable_field
    assert_equal ["$.format: expected string, got null"], errors_for("format" => nil)
  end

  def test_rejects_value_outside_enum
    assert_match(/\$\.event_type: "party" is not one of/, errors_for("event_type" => "party").first)
  end

  def test_rejects_values_that_do_not_match_the_pattern
    assert_match(/\$\.start_date/, errors_for("start_date" => "12 March 2026").first)
    assert_match(/\$\.start_date/, errors_for("start_date" => "2026-13-01").first)
    assert_match(/\$\.start_time/, errors_for("start_time" => "7 pm").first)
    assert_match(/\$\.price_currency/, errors_for("price_currency" => "€").first)
  end

  def test_pattern_must_match_the_whole_string
    assert_match(/\$\.start_date/, errors_for("start_date" => "2026-03-12\nextra").first)
  end

  def test_rejects_non_object_root
    assert_equal ["$: expected object, got array"], SchemaValidator.validate([1, 2], SCHEMA)
    assert_equal ["$: expected object, got string"], SchemaValidator.validate("hello", SCHEMA)
  end

  def test_validates_array_items
    schema = { "type" => "array", "items" => { "type" => "integer" } }
    assert_empty SchemaValidator.validate([1, 2.0], schema)
    assert_equal ["$[1]: expected integer, got string"], SchemaValidator.validate([1, "2"], schema)
  end
end
