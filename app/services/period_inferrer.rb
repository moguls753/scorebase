# frozen_string_literal: true

# Infers musical period from composer name using a YAML lookup table.
#
# Usage:
#   PeriodInferrer.infer("Bach, Johann Sebastian")  # => "Baroque"
#   PeriodInferrer.infer("Unknown Composer")        # => nil
#
class PeriodInferrer
  COMPOSER_PERIODS = YAML.load_file(
    Rails.root.join("config/composer_periods.yml")
  ).freeze

  def self.infer(composer)
    return nil if composer.blank?
    COMPOSER_PERIODS[composer]
  end
end
