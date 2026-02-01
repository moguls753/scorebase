class AddIsGroupRepresentativeToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :is_group_representative, :boolean
    add_index :scores, :is_group_representative, where: "is_group_representative = 1"
  end
end
