# Fix scores with corrupted composer names
#
# Usage: bin/rails runner script/fix_corrupted_composers.rb

COMPOSERS = {
  1750 => "Alexandrov, Alexander",
  3251 => "Mayer, John",
  13241 => "Tchaikovsky, Pyotr Ilyich",
  14768 => "Traditional",
  15250 => "Unknown",
  21211 => "Traditional",
  30932 => "Traditional",
  33662 => "Unknown",
  39988 => "Unknown",
  45854 => "Tchaikovsky, Pyotr Ilyich",
  47486 => "Traditional",
  47677 => "Traditional",
  48350 => "Traditional",
  48934 => "Unknown",
  49622 => "Brier, Tom",
  53257 => "Brier, Tom",
  60986 => "Traditional",
  67517 => "Sagisu, Shiro",
  71721 => "Unknown",
  72116 => "Traditional",
  75662 => "Tchaikovsky, Pyotr Ilyich",
  78151 => "Traditional",
  78733 => "Schütz, Heinrich",
  80140 => "Bon Jovi, Jon",
  83438 => "Traditional",
  83458 => "Unknown",
  85044 => "Pierpont, James",
  91774 => "Mozart, Wolfgang Amadeus",
  100510 => "Michael, George",
  101554 => "Traditional",
  104846 => "Unknown",
  105477 => "Traditional",
  106339 => "Masuda, Junichi",
  112721 => "Unknown",
  115169 => "Unknown",
  121827 => "Traditional",
  129976 => "Unknown",
  132418 => "Unknown",
  140177 => "Sagisu, Shiro",
  140548 => "Unknown",
  142127 => "Traditional",
  145670 => "Unknown",
  148010 => "Nakagawa, Kotaro",
  148415 => "Traditional",
  151309 => "Unknown",
  155903 => "Abreu, Zequinha de",
  158173 => "Traditional",
  164069 => "Bach, Johann Sebastian",
  164714 => "Traditional",
  171259 => "Unknown",
  176904 => "Unknown",
  177807 => "Traditional",
  184659 => "Unknown",
  185618 => "Unknown",
  188833 => "Traditional",
  191941 => "Mozart, Wolfgang Amadeus",
  198217 => "Shiratori, Sumio",
  198840 => "Unknown",
  208231 => "Sugiyama, Koichi",
  210725 => "Shiratori, Sumio",
  212960 => "Unknown",
  214944 => "Setoguchi, Tokichi",
  215475 => "Traditional",
  222604 => "Shimomura, Yoko",
  223317 => "Traditional",
  234603 => "Unknown",
  235126 => "Unknown",
  235343 => "Unknown",
  235551 => "Unknown",
  235969 => "Unknown",
  236262 => "Unknown",
  236291 => "Unknown"
}.freeze

updated = 0
COMPOSERS.each do |id, composer|
  score = Score.find_by(id: id)
  next unless score

  # Traditional/Unknown → failed (won't show on hub pages, won't re-process)
  # Real composers → pending (will go through normalizer)
  status = %w[Unknown Traditional].include?(composer) ? :failed : :pending
  score.update!(composer: composer, composer_status: status)
  puts "#{score.title.to_s.truncate(40)} -> #{composer}"
  updated += 1
end

puts
puts "Updated: #{updated} scores"
