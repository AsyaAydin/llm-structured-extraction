require_relative "test_helper"
require_relative "../utils/transport"
require "tmpdir"

class TransportTest < Minitest::Test
  def test_recorded_responses_replay_identically
    Dir.mktmpdir do |dir|
      body = api_response(output_text('{"a":1}'))
      recording = Transport::Recording.new(FakeTransport.new(200, body), File.join(dir, "nested"))
      assert_equal [200, body], recording.call("evt-1", {})

      status, replayed = Transport::Replay.new(File.join(dir, "nested")).call("evt-1", {})
      assert_equal 200, status
      assert_equal JSON.parse(body), JSON.parse(replayed)
    end
  end

  def test_non_json_bodies_and_failures_are_recorded_too
    Dir.mktmpdir do |dir|
      Transport::Recording.new(FakeTransport.new(502, "bad gateway"), dir).call("evt-1", {})
      assert_equal [502, "bad gateway"], Transport::Replay.new(dir).call("evt-1", {})
    end
  end

  def test_replay_reports_missing_recording
    Dir.mktmpdir do |dir|
      status, message = Transport::Replay.new(dir).call("evt-9", {})
      assert_equal 0, status
      assert_includes message, "no recorded response"
    end
  end

  def test_record_ids_cannot_escape_the_directory
    assert_equal File.join("dir", ".._.._etc_passwd.json"), Transport.path_for("dir", "../../etc/passwd")
  end

  def test_live_sends_bearer_token_to_responses_endpoint
    calls = []
    http = Object.new
    http.define_singleton_method(:post_json) do |url, body, headers:, timeout:|
      calls << [url, body, headers, timeout]
      [200, "{}"]
    end

    assert_equal [200, "{}"], Transport::Live.new(api_key: "sk-test", http: http).call("evt-1", { model: "m" })
    url, body, headers, timeout = calls.first
    assert_equal "https://api.openai.com/v1/responses", url
    assert_equal({ model: "m" }, body)
    assert_equal "Bearer sk-test", headers["Authorization"]
    assert_equal 120, timeout
  end
end
