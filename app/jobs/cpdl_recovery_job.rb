# frozen_string_literal: true

class CpdlRecoveryJob < ApplicationJob
  queue_as :default

  MIRROR_BASE_URL = "https://www1.cpdl.org/wiki/api.php"
  BYPASS_TIMEOUT_SECONDS = 30

  class TimedBypassClient
    def initialize(timeout:)
      @timeout = timeout
      @client = CloudflareBypassClient.new
    end

    def get(url)
      @client.get(url, timeout: @timeout)
    end
  end

  def perform(shard: nil, of: nil, limit: nil)
    importer = CpdlImporter.new(
      base_url: MIRROR_BASE_URL,
      http_client: TimedBypassClient.new(timeout: BYPASS_TIMEOUT_SECONDS)
    )
    stats = Hash.new(0)
    failed_ids = []

    s = scope(shard: shard, of: of)
    s = s.limit(limit) if limit

    s.find_each do |score|
      process_row(score, importer, stats, failed_ids)
      sleep 0.2
    rescue => e
      stats[:errors] += 1
      Rails.logger.warn "[CpdlRecovery] #{score.id} #{score.external_url} -> ERROR: #{e.message}"
    end

    write_failed_ids(failed_ids)
    log_summary(stats, shard, of)
  end

  private

  def scope(shard: nil, of: nil)
    s = Score.where(source: "cpdl")
             .where(mxl_path: [nil, ""])
             .where(voicing: [nil, ""])
             .where(part_names: [nil, ""])
             .where(pdf_path: [nil, ""])
             .where.not(external_url: [nil, ""])
    s = s.where("id % ? = ?", of, shard) if shard && of
    s.order(:id)
  end

  PAGE_PATH_RE = %r{/wiki/index\.php/(.+)\z}

  def page_title_from_url(url)
    match = url.to_s.match(PAGE_PATH_RE)
    return nil unless match
    URI.decode_www_form_component(match[1])
  end

  NEVER_OVERWRITE = %i[
    composer_normalized title_normalized
    voicing instruments genre period pedagogical_grade search_text
  ].freeze

  STATUS_FIELDS_KEEP_NORMALIZED = %i[
    voicing_status instruments_status composer_status
    period_status genre_status has_vocal_status
  ].freeze

  def build_delta(score, parsed)
    parsed = parsed.dup
    canonical = parsed.delete(:canonical_url) || parsed.delete(:external_url)
    delta = {}
    delta[:external_url] = canonical if canonical.present?

    parsed.each do |field, value|
      next if value.blank?
      next if NEVER_OVERWRITE.include?(field) && score.public_send(field).present?
      next if STATUS_FIELDS_KEEP_NORMALIZED.include?(field) && score.public_send(field) == "normalized"
      next if score.respond_to?(field) && score.public_send(field).present?
      delta[field] = value
    end
    delta
  end

  def process_row(score, importer, stats, failed_ids)
    title = page_title_from_url(score.external_url)
    return unless title

    page_data = importer.send(:fetch_page_content, title)
    if page_data.nil? || page_data.dig("wikitext", "*").blank? ||
       !importer.send(:has_score_content?, page_data["wikitext"]["*"])
      mark_stub(score)
      failed_ids << score.id
      stats[:marked_stub] += 1
      return
    end

    metadata = importer.send(:parse_score_metadata, title, page_data)
    if metadata.nil?
      mark_stub(score)
      failed_ids << score.id
      stats[:marked_stub] += 1
      return
    end

    new_canonical_url = canonical_url(page_data["title"] || title)
    if collision?(score, new_canonical_url)
      mark_collision(score)
      stats[:marked_collision] += 1
      return
    end

    metadata[:canonical_url] = new_canonical_url
    apply_recovery(score, metadata, stats)
  end

  def apply_recovery(score, metadata, stats)
    had_mxl     = metadata[:mxl_path].present?
    had_pdf     = metadata[:pdf_path].present?
    had_voicing = metadata[:voicing].present?
    delta = build_delta(score, metadata.except(:canonical_title))

    if had_voicing
      delta[:has_vocal]        = true
      delta[:has_vocal_status] = "normalized"
      delta[:voicing_status]   = "normalized"
    end

    if had_mxl || had_pdf
      score.update_columns(delta) if delta.any?
      stats[had_mxl ? :recovered_with_mxl : :recovered_with_pdf_only] += 1
    elsif had_voicing
      score.update_columns(delta) if delta.any?
      stats[:recovered_template_only] += 1
    else
      score.update_columns(rag_status: "failed", rag_failure_reason: "cpdl_no_files")
      stats[:marked_no_files] += 1
    end
  end

  def collision?(score, new_canonical_url)
    Score.where(source: "cpdl")
         .where(external_url: new_canonical_url)
         .where.not(id: score.id)
         .exists?
  end

  def mark_stub(score)
    score.update_columns(rag_status: "failed", rag_failure_reason: "cpdl_stub")
  end

  def mark_collision(score)
    score.update_columns(rag_status: "failed", rag_failure_reason: "cpdl_redirect_collision")
  end

  def canonical_url(title)
    "https://www.cpdl.org/wiki/index.php/#{URI.encode_www_form_component(title)}"
  end

  def write_failed_ids(ids)
    return if ids.empty?
    path = Rails.root.join("tmp/cpdl_stub_candidates.txt")
    File.open(path, "a") { |f| ids.each { |id| f.puts(id) } }
  end

  def log_summary(stats, shard, of)
    tag = (shard && of) ? " [shard #{shard}/#{of}]" : ""
    Rails.logger.info "[CpdlRecovery]#{tag} Complete: " \
      "mxl=#{stats[:recovered_with_mxl]} " \
      "pdf_only=#{stats[:recovered_with_pdf_only]} " \
      "template=#{stats[:recovered_template_only]} " \
      "stub=#{stats[:marked_stub]} " \
      "no_files=#{stats[:marked_no_files]} " \
      "collision=#{stats[:marked_collision]} " \
      "errors=#{stats[:errors]}"
  end
end
