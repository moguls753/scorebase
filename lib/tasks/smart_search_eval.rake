# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../smart_search_eval/runner"
require_relative "../smart_search_eval/analyzer"

namespace :smart_search do
  desc "Run the comprehensive smart-search evaluation against the local RAG service"
  task eval: :environment do
    SmartSearchEval::Runner.new.run
  end

  namespace :eval do
    desc "Analyze a smart-search eval JSON: bin/rails smart_search:eval:analyze JSON=eval/runs/run-XYZ.json"
    task analyze: :environment do
      json_path = ENV.fetch("JSON") do
        latest = Dir[Rails.root.join("eval/runs/run-*.json").to_s].max
        abort "Specify JSON=path/to/run.json (no runs found in eval/runs/)" unless latest
        latest
      end
      abort "Not a file: #{json_path}" unless File.file?(json_path)

      payload = JSON.parse(File.read(json_path))
      analyzer = SmartSearchEval::Analyzer.new(payload)
      report = analyzer.markdown_report

      reports_dir = Rails.root.join("eval/reports")
      FileUtils.mkdir_p(reports_dir)
      basename = File.basename(json_path, ".json").sub(/\Arun-/, "report-")
      output_path = reports_dir.join("#{basename}.md")
      File.write(output_path, report)

      puts report
      warn "\nWrote #{output_path}"
    end
  end
end
