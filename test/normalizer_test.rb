require_relative "test_helper"
require_relative "../utils/normalizer"

class NormalizerTest < Minitest::Test
  def test_removes_tags_and_keeps_block_boundaries_as_lines
    html = "<ul><li><strong>When:</strong> 12 March</li><li>Where: Istanbul</li></ul>"
    assert_equal "When: 12 March\nWhere: Istanbul", Normalizer.strip_html(html)
  end

  def test_table_cells_stay_on_the_row_line
    html = "<table><tr><td>Conference</td><td>9 September</td></tr><tr><td>Deadline</td><td>15 June</td></tr></table>"
    assert_equal "Conference 9 September\nDeadline 15 June", Normalizer.strip_html(html)
  end

  def test_drops_script_style_and_comments_with_their_content
    html = "<style>.a{color:red}</style><!-- note --><p>Hello</p><script>var price = 0;</script>"
    assert_equal "Hello", Normalizer.strip_html(html)
  end

  def test_decodes_common_entities
    assert_equal "Data & AI — €12 · £8", Normalizer.strip_html("Data&nbsp;&amp;&nbsp;AI &mdash; &euro;12 &middot; &#163;8")
    assert_equal "é", Normalizer.strip_html("&#xE9;")
  end

  def test_does_not_decode_twice
    assert_equal "&lt;b&gt;", Normalizer.strip_html("&amp;lt;b&amp;gt;")
  end

  def test_leaves_unknown_entities_untouched
    assert_equal "Karak&ouml;y", Normalizer.strip_html("Karak&ouml;y")
  end

  def test_keeps_comparison_signs_in_plain_text
    assert_equal "a < b and c > d", Normalizer.strip_html("a < b and c > d")
  end

  def test_handles_nil_and_non_strings
    assert_equal "", Normalizer.strip_html(nil)
    assert_equal "123", Normalizer.strip_html(123)
  end
end
