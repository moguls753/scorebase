class Avo::Actions::PermanentlyDeleteScores < Avo::BaseAction
  self.name = "Permanently Delete"
  self.message = "This will PERMANENTLY delete the selected scores. This cannot be undone!"
  self.confirm_button_label = "Delete Forever"
  self.cancel_button_label = "Cancel"

  def handle(query:, fields:, current_user:, resource:, **args)
    count = query.destroy_all.count
    succeed "Permanently deleted #{count} score(s)."
  end
end
