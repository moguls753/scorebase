# Clears imported MuseScore favorites data from PDMX scores.
# This data was misleading - it reflected MuseScore community preference (pop songs)
# rather than ScoreBase user engagement. The favorites field is now reserved for
# future Pro user favorites functionality.
#
# Popularity sort now uses views only (real ScoreBase traffic).
class ZeroOutImportedFavorites < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE scores SET favorites = 0 WHERE favorites > 0"
  end

  def down
    # Intentionally irreversible - imported data not worth preserving
    raise ActiveRecord::IrreversibleMigration, "Cannot restore imported MuseScore favorites"
  end
end
