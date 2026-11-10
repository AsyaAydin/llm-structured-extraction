require "csv"
require "json"

# Compares a runner.rb output CSV with hand-labelled expected values and prints
# exact-match accuracy per field.
#
# Usage: ruby eval.rb OUTPUT.csv EXPECTED.json
#
# EXPECTED.json maps record_id to the expected fields. A record that is missing
# from the CSV, or whose status is not "ok", counts as wrong for every field.
module Eval
  def self.matches?(expected, cell)
    cell = nil if cell.to_s.strip.empty?

    case expected
    when nil then cell.nil?
    when true, false then cell == expected.to_s
    when Numeric then !cell.nil? && Float(cell, exception: false) == expected.to_f
    else cell.to_s.strip == expected.to_s
    end
  end

  def self.compare(rows_by_id, expected)
    fields = expected.values.flat_map(&:keys).uniq
    correct = Hash.new(0)
    mismatches = []

    expected.each do |record_id, labels|
      row = rows_by_id[record_id]
      usable = row && row["status"] == "ok"

      fields.each do |field|
        next unless labels.key?(field)

        actual = usable ? row[field] : nil
        if usable && matches?(labels[field], actual)
          correct[field] += 1
        else
          got = usable ? actual.inspect : "no result (#{row ? row["status"] : "missing from output"})"
          mismatches << "#{record_id} #{field}: expected #{labels[field].inspect}, got #{got}"
        end
      end
    end

    totals = fields.to_h { |field| [field, expected.count { |_, labels| labels.key?(field) }] }
    { fields: fields, correct: correct, totals: totals, mismatches: mismatches }
  end

  def self.report(result)
    lines = ["| field | correct | total | accuracy |", "|---|---|---|---|"]
    result[:fields].each do |field|
      lines << row_line(field, result[:correct][field], result[:totals][field])
    end
    lines << row_line("**all fields**", result[:correct].values.sum, result[:totals].values.sum)

    unless result[:mismatches].empty?
      lines << ""
      lines << "Mismatches:"
      result[:mismatches].each { |mismatch| lines << "- #{mismatch}" }
    end

    lines.join("\n")
  end

  def self.row_line(label, correct, total)
    percent = total.zero? ? "n/a" : "#{(100.0 * correct / total).round}%"
    "| #{label} | #{correct} | #{total} | #{percent} |"
  end

  private_class_method :row_line
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: ruby eval.rb OUTPUT.csv EXPECTED.json" unless ARGV.size == 2

  output_path, expected_path = ARGV
  [output_path, expected_path].each { |path| abort "File not found: #{path}" unless File.exist?(path) }

  rows_by_id = CSV.read(output_path, headers: true, encoding: "UTF-8").to_h { |row| [row["record_id"], row.to_h] }
  expected = JSON.parse(File.read(expected_path))

  puts Eval.report(Eval.compare(rows_by_id, expected))
end
