require_relative "test_helper"
require_relative "../eval"

class EvalTest < Minitest::Test
  def test_matches_compares_csv_cells_with_typed_labels
    assert Eval.matches?(nil, nil)
    assert Eval.matches?(nil, "")
    refute Eval.matches?(nil, "Berlin")
    assert Eval.matches?(true, "true")
    refute Eval.matches?(false, "true")
    refute Eval.matches?(false, nil)
    assert Eval.matches?(349, "349.0")
    assert Eval.matches?(12.5, "12.5")
    refute Eval.matches?(349, "249")
    refute Eval.matches?(349, nil)
    assert Eval.matches?("Berlin", "Berlin")
    refute Eval.matches?("Berlin", "berlin")
  end

  def test_compare_counts_per_field_and_lists_mismatches
    expected = {
      "a" => { "city" => "Berlin", "price_amount" => 12 },
      "b" => { "city" => nil, "price_amount" => nil },
      "c" => { "city" => "Izmir", "price_amount" => 750 }
    }
    rows = {
      "a" => { "status" => "ok", "city" => "Berlin", "price_amount" => "15" },
      "b" => { "status" => "ok", "city" => nil, "price_amount" => nil },
      "c" => { "status" => "invalid_json", "city" => nil, "price_amount" => nil }
    }

    result = Eval.compare(rows, expected)
    assert_equal({ "city" => 2, "price_amount" => 1 }, result[:correct])
    assert_equal({ "city" => 3, "price_amount" => 3 }, result[:totals])
    assert_equal 3, result[:mismatches].size
    assert_includes result[:mismatches], 'a price_amount: expected 12, got "15"'
    assert_includes result[:mismatches], 'c city: expected "Izmir", got no result (invalid_json)'

    report = Eval.report(result)
    assert_includes report, "| city | 2 | 3 | 67% |"
    assert_includes report, "| **all fields** | 3 | 6 | 50% |"
  end

  def test_records_missing_from_output_count_as_wrong
    result = Eval.compare({}, { "a" => { "city" => "Berlin" } })
    assert_equal 0, result[:correct]["city"]
    assert_includes result[:mismatches].first, "missing from output"
  end
end
