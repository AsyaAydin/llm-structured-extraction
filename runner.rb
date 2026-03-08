require_relative "utils/normalizer"
require_relative "llm_extractor"

require "time"
require "csv"
require "json"

openai_key = ENV["OPENAI_API_KEY"] || ""
prompt_id = ENV["LLM_PROMPT_ID"] || ""
prompt_version = ENV["LLM_PROMPT_VERSION"] || ""

abort "OPENAI_API_KEY is required" if openai_key.empty?
abort "LLM_PROMPT_ID is required" if prompt_id.empty?
abort "LLM_PROMPT_VERSION is required" if prompt_version.empty?
abort "Usage: ruby runner.rb path/to/input.json" if ARGV.empty?

input_path = ARGV[0]
abort "Input file not found: #{input_path}" unless File.exist?(input_path)

begin
  records = JSON.parse(File.read(input_path))
rescue JSON::ParserError => e
  abort "Invalid JSON in input file: #{e.message}"
end

abort "Input JSON must be an array" unless records.is_a?(Array)

extractor = LlmExtractor.new(
  api_key: openai_key,
  prompt_id: prompt_id,
  prompt_version: prompt_version
)

timestamp = Time.now.utc.iso8601.gsub(":", "-")
outfile = File.join(Dir.pwd, "structured_records_#{timestamp}.csv")

rows = []

records.each_with_index do |record, index|
  input_name = record["input_name"].to_s
  title = record["title"].to_s
  description = record["description"].to_s

  puts "[#{index + 1}/#{records.size}] Processing: #{input_name.empty? ? "(unnamed record)" : input_name}"

  begin
    cleaned_description = Normalizer.strip_html(description)[0, 4000]

    extracted = extractor.extract_record(
      input_name: input_name,
      title: title,
      description: cleaned_description
    )

    rows << {
      "record_id" => record["record_id"],
      "input_name" => input_name,
      "title" => title,
      "description_excerpt" => cleaned_description[0, 300],
      "structured_output" => JSON.generate(extracted)
    }

    puts "  saved"
  rescue Net::ReadTimeout, Net::OpenTimeout
    warn "  timeout for #{input_name}, skipped"
  rescue StandardError => e
    warn "  error for #{input_name}: #{e.message}"
  end
end

if rows.any?
  headers = rows.first.keys

  CSV.open(outfile, "wb:UTF-8", col_sep: ";", write_headers: true, headers: headers) do |csv|
    rows.each do |row|
      csv << headers.map { |header| row[header].to_s.dup.force_encoding("UTF-8").scrub("?") }
    end
  end
end

puts "\nDone. Output: #{outfile}"
