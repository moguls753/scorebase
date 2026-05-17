# frozen_string_literal: true

namespace :smd do
  desc "Backfill SMD title column from clean_title (intact rows) or derive from JSON-LD name (truncated rows). DRY_RUN=1 to preview."
  task backfill_title: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    puts "Mode: #{dry_run ? 'DRY RUN (no writes)' : 'WRITE'}"
    puts

    # Strip SMD's marketing tail (" by <composer> <category> [Digital Sheet Music|Ensemble]"
    # or bare " by <composer>"). Rightmost lowercase " by " preserves song titles
    # that legitimately contain " by " (e.g. "Down by the Riverside").
    strip_marketing_tail = ->(raw) {
      next raw if raw.blank?
      idx = raw.rindex(" by ")
      idx ? raw[0...idx] : raw
    }

    smd = Score.where(source: "smd")

    # "Truncated" = clean_title ends in a literal backslash, the signature of
    # the metadata_extractor regex stopping mid-escape sequence.
    truncation_pattern = "%\\"

    intact_scope = smd
      .where.not(clean_title: nil)
      .where.not(clean_title: "")
      .where("clean_title NOT LIKE ?", truncation_pattern)
      .where("title <> clean_title")

    corrupt_scope = smd.where("clean_title IS NULL OR clean_title = '' OR clean_title LIKE ?", truncation_pattern)

    total = smd.count
    intact_count = intact_scope.count
    corrupt_count = corrupt_scope.count

    puts "SMD rows total: #{total}"
    puts "  Pass 1 (copy clean_title -> title): #{intact_count}"
    puts "  Pass 2 (derive from title):         #{corrupt_count}"
    puts

    if dry_run
      puts "DRY RUN — Pass 2 samples:"
      corrupt_scope.limit(3).pluck(:id, :title, :clean_title).each do |id, t, c|
        puts "  id=#{id}"
        puts "    title       : #{t.to_s.truncate(120)}"
        puts "    clean_title : #{c.inspect[0, 80]}"
        puts "    derived     : #{strip_marketing_tail.call(t).to_s.truncate(120)}"
      end
      puts
      puts "DRY RUN — no writes performed."
      next
    end

    print "Pass 1... "
    intact_scope.update_all("title = clean_title")
    puts "done."

    print "Pass 2 "
    changed = 0
    corrupt_scope.pluck(:id, :title).each do |id, title|
      candidate = strip_marketing_tail.call(title)
      next if candidate.blank?
      # Overwrite clean_title too — display_title and search_text_generator prefer
      # clean_title.presence over title, so leaving the truncated value behind would
      # keep the bug visible until step 3 lands.
      Score.where(id: id).update_all(title: candidate, clean_title: candidate)
      changed += 1
      print "." if changed.positive? && (changed % 100).zero?
    end
    puts " done (#{changed} of #{corrupt_count} changed)."
    puts
    puts "Backfill complete. clean_title left intact (drop in a follow-up migration once readers move off it)."
  end
end
