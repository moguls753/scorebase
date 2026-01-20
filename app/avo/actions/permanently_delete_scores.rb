class Avo::Actions::PermanentlyDeleteScores < Avo::BaseAction
  self.name = "Permanently Delete"
  self.message = "This will PERMANENTLY delete the selected scores. This cannot be undone!"
  self.confirm_button_label = "Delete Forever"
  self.cancel_button_label = "Cancel"

  def handle(query:, fields:, current_user:, resource:, **args)
    records = query.to_a
    count = records.size
    records.each(&:destroy!)
    succeed "Permanently deleted #{count} score(s)."
    redirect_to avo.resources_scores_path
  rescue => e
    fail "Failed to delete: #{e.message}"
  end
end
