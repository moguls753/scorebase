# Normalize remaining pending composers that are already in canonical format
#
# Usage: bin/rails runner script/normalize_pending_composers.rb

composers = [
  'Mayer, John',
  'Tchaikovsky, Pyotr Ilyich',
  'Sagisu, Shiro',
  'Bon Jovi, Jon',
  'Pierpont, James',
  'Michael, George',
  'Masuda, Junichi',
  'Nakagawa, Kotaro',
  'Abreu, Zequinha de',
  'Shiratori, Sumio',
  'Sugiyama, Koichi',
  'Setoguchi, Tokichi',
  'Shimomura, Yoko'
]

composers.each do |c|
  # Add to cache (same name = already canonical)
  ComposerMapping.find_or_create_by!(original_name: c) do |m|
    m.normalized_name = c
    m.source = 'manual'
  end

  # Mark as normalized
  count = Score.where(composer: c, composer_status: 'pending').update_all(composer_status: 'normalized')
  puts "#{c} -> #{count} scores normalized"
end

puts
puts "Still pending: #{Score.composer_pending.count}"
