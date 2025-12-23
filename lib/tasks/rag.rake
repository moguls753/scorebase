# frozen_string_literal: true

namespace :rag do
  desc "Show normalization and RAG pipeline stats"
  task stats: :environment do
    puts "Normalization Status"
    puts "=" * 50
    puts
    puts "Composer:"
    Score.group(:composer_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "Genre:"
    Score.group(:genre_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "Period:"
    Score.group(:period_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "Instruments:"
    Score.group(:instruments_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "=" * 50
    puts "RAG Pipeline:"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "Ready for RAG: #{Score.where(rag_status: 'ready').count}"
  end
end
