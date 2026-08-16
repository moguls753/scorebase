# frozen_string_literal: true

# Which partner editions a free score should offer (docs/stretta-import-plan.md §13).
#
# The rule: never two buy boxes for the same work. What decides which partner wins
# a contested work is the fit to *this* score's scoring, not which partner exists —
# equal fit keeps SMD, which carries the richer metadata.
class PartnerEditions
  Result = Data.define(:smd, :stretta)

  def self.for(score) = new(score).call

  def initialize(score)
    @score = score
  end

  def call
    smd = @score.professional_editions.with_attached_thumbnail_image.to_a
    stretta = @score.stretta_editions.with_attached_thumbnail_image.to_a
    return Result.new(smd: smd, stretta: stretta) if smd.empty? || stretta.empty?

    resolve(smd, stretta)
  end

  private

  def resolve(smd, stretta)
    rivals = smd.index_by { |edition| MusicText.normalize(edition.title) }
    beaten = Set.new

    kept = stretta.select do |edition|
      rival = rivals[MusicText.normalize(edition.title)]
      next true if rival.nil?
      next false unless stretta_wins?(edition, rival)

      beaten << rival.id
      true
    end

    Result.new(smd: smd.reject { |edition| beaten.include?(edition.id) }, stretta: kept)
  end

  # Scoring first: an edition for the wrong instrument is no use however close the
  # shop. Only where both fit equally does the locale decide.
  def stretta_wins?(edition, rival)
    stretta_fits = fits?(SmdMatchFinder.instrument_family(edition.instruments))
    smd_fits = fits?(SmdMatchFinder.smd_family(rival.main_instrument))
    return stretta_fits if stretta_fits != smd_fits

    german_locale?
  end

  def german_locale?
    I18n.locale == :de
  end

  def fits?(family)
    SmdMatchFinder.compatible?(free_family, family)
  end

  def free_family
    @free_family ||= SmdMatchFinder.free_family(@score.voicing, @score.is_instrumental, @score.instruments)
  end
end
