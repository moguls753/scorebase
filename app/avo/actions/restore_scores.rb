class Avo::Actions::RestoreScores < Avo::BaseAction
  self.name = "Restore"
  self.message = "This will restore the selected scores."
  self.confirm_button_label = "Restore"
  self.cancel_button_label = "Cancel"

  def handle(query:, fields:, current_user:, resource:, **args)
    count = query.update_all(deleted_at: nil)
    succeed "Restored #{count} score(s)."
  rescue => e
    fail "Failed to restore: #{e.message}"
  end
end
