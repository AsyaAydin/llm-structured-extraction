require "csv"
require "json"
require "optparse"
require "time"

require_relative "utils/normalizer"
require_relative "utils/transport"
require_relative "llm_extractor"

ROOT = __dir__
PROMPT_DIR = File.join(ROOT, "prompts", "event_extraction")
SCHEMA_PATH = File.join(ROOT, "schema", "event.schema.json")
MAX_DESCRIPTION_CHARS = 4000
BASE_COLUMNS = %w[record_id title status error].freeze

def build_input(record, text)
  <<~INPUT
    Source: #{record["source"]}
    Posted on: #{record["posted_on"]}
    Title: #{record["title"]}

    Announcement:
    #{text}
  INPUT
end

# Returns one output row. A record that cannot be processed still gets a row,
# with a status and an error message, so failures stay visible in the CSV.
def process_record(record, index, extractor)
  fallback_id = (index + 1).to_s
  unless record.is_a?(Hash)
    return { "record_id" => fallback_id, "status" => "invalid_record", "error" => "record is not a JSON object" }
  end

  row = {
    "record_id" => (record["record_id"] || fallback_id).to_s,
    "title" => record["title"].to_s
  }

  text = Normalizer.strip_html(record["description"])
  if text.empty?
    return row.merge("status" => "invalid_record", "error" => "description is empty")
  end

  if text.length > MAX_DESCRIPTION_CHARS
    warn "  description truncated from #{text.length} to #{MAX_DESCRIPTION_CHARS} characters"
    text = text[0, MAX_DESCRIPTION_CHARS]
  end

  result = extractor.extract(record_id: row["record_id"], input: build_input(record, text))
  row.merge("status" => result.status, "error" => result.error).merge(result.data || {})
rescue StandardError => e
  (row || { "record_id" => fallback_id }).merge("status" => "error", "error" => "#{e.class}: #{e.message}")
end

def csv_cell(value)
  value.is_a?(String) ? value.dup.force_encoding("UTF-8").scrub("?") : value
end

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby runner.rb [options] path/to/input.json"
  opts.on("--replay DIR", "Read recorded API responses from DIR instead of calling the API (no API key needed)") do |dir|
    options[:replay] = dir
  end
  opts.on("--record DIR", "Call the API and also save each raw response to DIR") do |dir|
    options[:record] = dir
  end
  opts.on("--out FILE", "CSV output path (default: structured_records_<timestamp>.csv)") do |file|
    options[:out] = file
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  abort "#{e.message}\n\n#{parser}"
end

abort parser.to_s if ARGV.empty?
abort "--replay and --record cannot be used together" if options[:replay] && options[:record]

input_path = ARGV[0]
abort "Input file not found: #{input_path}" unless File.exist?(input_path)

begin
  records = JSON.parse(File.read(input_path))
rescue JSON::ParserError => e
  abort "Invalid JSON in input file: #{e.message}"
end

abort "Input JSON must be an array" unless records.is_a?(Array)

prompt_version = ENV["LLM_PROMPT_VERSION"].to_s.strip
prompt_version = "1" if prompt_version.empty?
abort "LLM_PROMPT_VERSION must be a number" unless prompt_version.match?(/\A\d+\z/)

prompt_path = File.join(PROMPT_DIR, "v#{prompt_version}.md")
abort "Prompt not found: #{prompt_path}" unless File.exist?(prompt_path)

schema = JSON.parse(File.read(SCHEMA_PATH))

transport =
  if options[:replay]
    abort "Replay directory not found: #{options[:replay]}" unless Dir.exist?(options[:replay])
    Transport::Replay.new(options[:replay])
  else
    api_key = ENV["OPENAI_API_KEY"].to_s.strip
    abort "OPENAI_API_KEY is required (or use --replay DIR to run without one)" if api_key.empty?
    live = Transport::Live.new(api_key: api_key)
    options[:record] ? Transport::Recording.new(live, options[:record]) : live
  end

model = ENV["OPENAI_MODEL"].to_s.strip
extractor = LlmExtractor.new(
  transport: transport,
  instructions: File.read(prompt_path),
  schema: schema,
  schema_name: "event",
  model: model.empty? ? LlmExtractor::DEFAULT_MODEL : model
)

timestamp = Time.now.utc.iso8601.gsub(":", "-")
outfile = options[:out] || File.join(Dir.pwd, "structured_records_#{timestamp}.csv")
columns = BASE_COLUMNS + schema.fetch("properties").keys
ok_count = 0

# Rows are written as they are produced, so an interrupted run keeps its results.
CSV.open(outfile, "w:UTF-8", write_headers: true, headers: columns) do |csv|
  records.each_with_index do |record, index|
    row = process_record(record, index, extractor)
    csv << columns.map { |column| csv_cell(row[column]) }
    csv.flush

    ok_count += 1 if row["status"] == "ok"
    detail = row["status"] == "ok" ? "ok" : "#{row["status"]}: #{row["error"]}"
    puts "[#{index + 1}/#{records.size}] #{row["record_id"]} #{detail}"
  end
end

failed_count = records.size - ok_count
puts "\nDone. #{records.size} records: #{ok_count} ok, #{failed_count} failed. Output: #{outfile}"
exit 1 if failed_count.positive?
