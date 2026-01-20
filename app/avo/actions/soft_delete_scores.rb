class Avo::Actions::SoftDeleteScores < Avo::BaseAction
  self.name = "Delete (recoverable)"
  self.message = "This will soft-delete the selected scores. They can be restored within 100 days."
  self.confirm_button_label = "Delete"
  self.cancel_button_label = "Cancel"

  def handle(query:, fields:, current_user:, resource:, **args)
    count = query.update_all(deleted_at: Time.current)
    succeed "Deleted #{count} score(s). They can be restored from the Deleted filter."
  end
end
