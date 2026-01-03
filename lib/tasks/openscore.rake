namespace :openscore do
  desc "Import all scores from OpenScore Lieder corpus"
  task import: :environment do
    OpenscoreImporter.new.import!
  end

  desc "Import a sample of OpenScore scores. Use openscore:sample[100]"
  task :sample, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 10).to_i
    OpenscoreImporter.new(limit: limit).import!
  end

  namespace :quartets do
    desc "Import all scores from OpenScore String Quartets corpus"
    task import: :environment do
      OpenscoreQuartetsImporter.new.import!
    end

    desc "Import a sample of OpenScore String Quartets. Use openscore:quartets:sample[100]"
    task :sample, [:limit] => :environment do |_t, args|
      limit = (args[:limit] || 10).to_i
      OpenscoreQuartetsImporter.new(limit: limit).import!
    end
  end

  desc "Show OpenScore import statistics"
  task stats: :environment do
    total = Score.where(source: "openscore").count
    puts "OpenScore Lieder Scores: #{total}"
    puts ""

    if total > 0
      puts "By composer (top 10):"
      Score.where(source: "openscore")
        .group(:composer)
        .order("count_all DESC")
        .limit(10)
        .count
        .each { |composer, count| puts "  #{composer || 'Unknown'}: #{count}" }

      puts ""
      puts "With lyrics: #{Score.where(source: 'openscore', has_extracted_lyrics: true).count}"
      puts "With MusicXML: #{Score.where(source: 'openscore').where.not(mxl_path: [nil, '']).count}"

      puts ""
      puts "With key signature: #{Score.where(source: 'openscore').where.not(key_signature: [nil, '']).count}"
      puts "With time signature: #{Score.where(source: 'openscore').where.not(time_signature: [nil, '']).count}"

      puts ""
      puts "By period:"
      Score.where(source: "openscore")
        .group(:period)
        .order("count_all DESC")
        .count
        .each { |period, count| puts "  #{period || 'Unknown'}: #{count}" }
    end
  end

  desc "Clear all OpenScore scores from database"
  task clear: :environment do
    count = Score.where(source: "openscore").count
    print "This will delete #{count} OpenScore scores. Continue? (y/N) "
    confirm = $stdin.gets.chomp.downcase

    if confirm == "y"
      Score.where(source: "openscore").delete_all
      puts "Deleted #{count} OpenScore scores."
    else
      puts "Aborted."
    end
  end
end
