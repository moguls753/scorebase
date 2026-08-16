# frozen_string_literal: true

# Matches free scores to Stretta's publisher editions of the same work
# (docs/stretta-import-plan.md §13).
#
# Same shape as SmdMatchFinder — exact normalised title plus composer surname,
# generic form titles stoplisted — but reading Stretta's own columns. Its
# `instruments` already holds ScoreBase's English vocabulary, so both sides of a
# family comparison go through the same classifier and no second family map exists.
# Title match alone is not a reliable "same edition" signal, which is why the
# family ranking below decides ordering and PartnerMatchConverge caps the result.
class StrettaMatchFinder
  MAX_MATCHES = 3

  # Product forms a browsing user never buys: an orchestral part or a bare
  # conductor's score is not an edition they can play from.
  PART_RANKS = { 5 => 0, 10 => 0, 20 => 0, 30 => 0, 50 => 0, 40 => 1, 60 => 2, 70 => 2, 90 => 3 }.freeze
  DEFAULT_PART_RANK = 1

  # Rows: [id, title, composer, price_eur, instruments, group_rank]
  def self.build_index(rows, index = {})
    rows.each do |id, title, composer, price, instruments, group_rank|
      key = MusicText.normalize(title)
      next if key.empty?

      # -"str" interns, same as SmdMatchFinder's index and for the same reason.
      (index[key] ||= []) << [ id, price&.to_f, -MusicText.surname(composer),
                               SmdMatchFinder.instrument_family(instruments),
                               PART_RANKS.fetch(group_rank, DEFAULT_PART_RANK) ]
    end
    index
  end

  def self.matches_for(title, composer, index, free_family: nil)
    key = MusicText.normalize(title)
    return [] if key.empty? || SmdMatchFinder::GENERIC_FORM_TITLES.include?(key)

    wanted = MusicText.surname(composer)
    return [] if wanted.empty?

    candidates = (index[key] || []).select { |_, _, surname, _, _| surname == wanted }
    rank(candidates, free_family).map(&:first)
  end

  # Family match first, then playable form before single parts, then price DESC as
  # a proxy for the fuller edition, then id.
  def self.rank(entries, free_family = nil)
    entries.sort_by do |id, price, _, family, part_rank|
      [ SmdMatchFinder.compatible?(free_family, family) ? 0 : 1,
        SmdMatchFinder.ensemble_mismatch?(free_family, family) ? 1 : 0,
        part_rank, price.nil? ? 1 : 0, -(price || 0), id ]
    end
  end
end
