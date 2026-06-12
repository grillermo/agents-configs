#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "set"
require "time"

class ProductionTranscriptPreprocessor
  Result = Struct.new(:files_written, :rows_skipped, :errors, :early_exit_id, keyword_init: true)

  NAME_POOL = %w[
    Alex Blair Casey Drew Ellis Finley Gray Harper Indy Jules Kai Logan Morgan
    Nico Oakley Parker Quinn Reese Sage Taylor Urban Val Wren Xavi Yael Zion
    Avery Bailey Cameron Dakota Emery Frankie Hayden Jamie Kendall Lennon Micah
    Noa Peyton Remy Rowan Skyler Tatum
  ].freeze

  def initialize(
    input_path: "production-transcript.csv",
    output_dir: "production-transcript-conversations",
    id_column: "id",
    status_column: "status",
    response_column: "response",
    completed_status: "COMPLETED"
  )
    @input_path = input_path
    @output_dir = output_dir
    @id_column = id_column
    @status_column = status_column
    @response_column = response_column
    @completed_status = completed_status
    @speaker_names = SpeakerNames.new
  end

  def run
    FileUtils.mkdir_p(output_dir)

    files_written = 0
    rows_skipped = 0
    errors = []
    early_exit_id = nil
    seen = processed_ids

    CSV.foreach(input_path, headers: true) do |row|
      row_id = row[id_column]

      if seen.include?(row_id)
        early_exit_id = row_id
        break
      end

      unless row[status_column] == completed_status
        rows_skipped += 1
        next
      end

      write_markdown(row)
      files_written += 1
    rescue JSON::ParserError, KeyError, ArgumentError => e
      errors << "#{row_id || "unknown"}: #{e.class}: #{e.message}"
    end

    Result.new(files_written:, rows_skipped:, errors:, early_exit_id:)
  end

  private

  attr_reader :input_path, :output_dir, :id_column, :status_column,
              :response_column, :completed_status, :speaker_names

  def write_markdown(row)
    id = fetch_required(row, id_column)
    response = JSON.parse(fetch_required(row, response_column))
    epoch = Time.parse(fetch_required(row, "created_at")).utc.to_i
    path = File.join(output_dir, "#{epoch}_#{safe_filename(id)}.md")

    File.write(path, markdown_for(row, response), mode: "w", encoding: "UTF-8")
  end

  def markdown_for(row, response)
    utterances = utterances_from(response)

    lines = [
      "# Conversation #{row[id_column]}",
      "",
      metadata_line("Source row id", row[id_column]),
      metadata_line("Provider", row["provider"]),
      metadata_line("Provider response id", response["id"]),
      metadata_line("Created at", row["created_at"]),
      metadata_line("Updated at", row["updated_at"]),
      metadata_line("Language", row["language"]),
      "",
      "## Speaker dictionary",
      ""
    ]

    speaker_ids = utterances.map { |utterance| speaker_id_for(utterance) }.uniq
    speaker_ids.each { |speaker_id| lines << "- `#{speaker_id}` = #{speaker_names.name_for(speaker_id)}" }

    lines += ["", "## Conversation", ""]

    utterances.each do |utterance|
      speaker_name = speaker_names.name_for(speaker_id_for(utterance))
      lines << "**#{format_timestamp(utterance["start"])} #{speaker_name}**"
      lines << ""
      lines << clean_text(utterance["text"])
      lines << ""
    end

    lines.join("\n").rstrip + "\n"
  end

  def utterances_from(response)
    utterances = Array(response["utterances"]).sort_by do |utterance|
      [timestamp_sort_value(utterance["start"]), timestamp_sort_value(utterance["end"])]
    end

    return utterances unless utterances.empty?

    text = clean_text(response["text"])
    return [] if text.empty?

    [{ "speaker" => "transcript", "start" => nil, "end" => nil, "text" => text }]
  end

  def speaker_id_for(utterance)
    speaker = utterance["speaker"] || utterance.dig("words", 0, "speaker")
    speaker.to_s.strip.empty? ? "unknown" : speaker.to_s
  end

  def fetch_required(row, column)
    value = row[column]
    fail KeyError, "missing #{column.inspect}" if value.nil? || value.empty?

    value
  end

  def metadata_line(label, value)
    return "#{label}: " if value.nil? || value.empty?

    "#{label}: `#{value}`"
  end

  def clean_text(text)
    text.to_s.strip
  end

  def format_timestamp(milliseconds)
    return "unknown" if milliseconds.nil?

    total_milliseconds = milliseconds.to_i
    milliseconds_part = total_milliseconds % 1_000
    total_seconds = total_milliseconds / 1_000
    seconds = total_seconds % 60
    minutes = (total_seconds / 60) % 60
    hours = total_seconds / 3_600

    format("%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds_part)
  end

  def timestamp_sort_value(value)
    value.nil? ? Float::INFINITY : value.to_i
  end

  def safe_filename(value)
    value.to_s.gsub(%r{[^\w.-]}, "_")
  end

  def processed_ids
    pattern = File.join(output_dir, "*.md")
    Dir.glob(pattern).each_with_object(Set.new) do |path, set|
      name = File.basename(path, ".md")
      # Strip leading epoch prefix if present (integer prefix, no underscores)
      id = name.match?(/\A\d+_/) ? name.split("_", 2)[1] : name
      set.add(id)
    end
  end

  class SpeakerNames
    def initialize
      @names_by_id = {}
    end

    def name_for(speaker_id)
      @names_by_id[speaker_id] ||= next_name
    end

    private

    def next_name
      NAME_POOL[@names_by_id.size] || "Speaker #{@names_by_id.size + 1}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  input_path = ARGV[0] || "production-transcript.csv"
  output_dir = ARGV[1] || "production-transcript-conversations"

  result = ProductionTranscriptPreprocessor.new(
    input_path: input_path,
    output_dir: output_dir
  ).run

  puts "Wrote #{result.files_written} markdown files to #{output_dir}"
  puts "Skipped #{result.rows_skipped} non-COMPLETED rows"

  unless result.errors.empty?
    warn "Encountered #{result.errors.size} errors:"
    result.errors.each { |error| warn "  #{error}" }
    exit 1
  end
end
