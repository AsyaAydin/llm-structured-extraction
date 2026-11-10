require_relative "test_helper"
require "csv"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs runner.rb as a subprocess, the way a user would.
class RunnerTest < Minitest::Test
  RUNNER = File.join(ROOT, "runner.rb")
  INPUT = File.join(FIXTURES, "input.json")
  RECORDED = File.join(FIXTURES, "recorded")
  EXAMPLE_INPUT = File.join(ROOT, "examples", "events.json")
  EXAMPLE_RECORDED = File.join(ROOT, "examples", "recorded")
  EXAMPLE_OUTPUT = File.join(ROOT, "examples", "output.csv")

  def run_runner(*args, env: {})
    clean_env = { "OPENAI_API_KEY" => nil, "OPENAI_MODEL" => nil, "LLM_PROMPT_VERSION" => nil }.merge(env)
    Open3.capture3(clean_env, RbConfig.ruby, RUNNER, *args)
  end

  def test_replay_writes_one_row_per_record_with_status_and_typed_columns
    Dir.mktmpdir do |dir|
      out = File.join(dir, "out.csv")
      stdout, _stderr, status = run_runner("--replay", RECORDED, "--out", out, INPUT)

      rows = CSV.read(out, headers: true)
      assert_equal %w[record_id title status error event_type start_date start_time format city is_free
                      price_amount price_currency topic], rows.headers
      assert_equal %w[ok-1 prose-1 missing-1 4 empty-1], rows["record_id"]
      assert_equal %w[ok invalid_json api_error invalid_record invalid_record], rows["status"]

      ok = rows[0]
      assert_equal "2026-03-12", ok["start_date"]
      assert_equal "true", ok["is_free"]
      assert_nil ok["price_amount"]
      assert_nil ok["error"]

      assert_nil rows[1]["event_type"], "failed records must not carry extracted values"
      assert_includes rows[2]["error"], "no recorded response"
      assert_equal "record is not a JSON object", rows[3]["error"]
      assert_equal "description is empty", rows[4]["error"]

      assert_includes stdout, "5 records: 1 ok, 4 failed"
      assert_equal 1, status.exitstatus, "a run with failed records must not exit 0"
    end
  end

  def test_all_ok_run_exits_zero
    Dir.mktmpdir do |dir|
      input = File.join(dir, "one.json")
      File.write(input, JSON.generate([JSON.parse(File.read(INPUT)).first]))
      stdout, _stderr, status = run_runner("--replay", RECORDED, "--out", File.join(dir, "out.csv"), input)

      assert_includes stdout, "1 records: 1 ok, 0 failed"
      assert_equal 0, status.exitstatus
    end
  end

  def test_empty_input_still_writes_a_header_only_file
    Dir.mktmpdir do |dir|
      input = File.join(dir, "empty.json")
      out = File.join(dir, "out.csv")
      File.write(input, "[]")
      _stdout, _stderr, status = run_runner("--replay", RECORDED, "--out", out, input)

      assert_equal 0, status.exitstatus
      assert_equal 1, File.readlines(out).size
      assert File.read(out).start_with?("record_id,title,status,error,event_type")
    end
  end

  def test_live_mode_requires_an_api_key
    _stdout, stderr, status = run_runner(INPUT)
    assert_equal 1, status.exitstatus
    assert_includes stderr, "OPENAI_API_KEY is required"
  end

  def test_usage_and_argument_errors
    _stdout, stderr, status = run_runner
    assert_equal 1, status.exitstatus
    assert_includes stderr, "Usage: ruby runner.rb"

    _stdout, stderr, = run_runner("--replay", RECORDED, "--record", RECORDED, INPUT)
    assert_includes stderr, "cannot be used together"

    _stdout, stderr, = run_runner("--replay", RECORDED, "does-not-exist.json")
    assert_includes stderr, "Input file not found"

    _stdout, stderr, = run_runner("--replay", File.join(FIXTURES, "nope"), INPUT)
    assert_includes stderr, "Replay directory not found"
  end

  def test_unknown_prompt_version_is_rejected
    _stdout, stderr, status = run_runner("--replay", RECORDED, INPUT, env: { "LLM_PROMPT_VERSION" => "99" })
    assert_equal 1, status.exitstatus
    assert_includes stderr, "Prompt not found"

    _stdout, stderr, = run_runner("--replay", RECORDED, INPUT, env: { "LLM_PROMPT_VERSION" => "../x" })
    assert_includes stderr, "LLM_PROMPT_VERSION must be a number"
  end

  # The committed example output must be exactly what the code produces from
  # the committed recorded responses.
  def test_committed_example_output_is_reproducible
    skip "no recorded example run in this checkout" unless Dir.exist?(EXAMPLE_RECORDED)

    Dir.mktmpdir do |dir|
      out = File.join(dir, "out.csv")
      run_runner("--replay", EXAMPLE_RECORDED, "--out", out, EXAMPLE_INPUT)
      assert_equal File.read(EXAMPLE_OUTPUT), File.read(out)
    end
  end
end
