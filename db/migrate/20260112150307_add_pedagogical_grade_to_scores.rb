class AddPedagogicalGradeToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :pedagogical_grade, :string
    add_column :scores, :pedagogical_grade_de, :string
    add_column :scores, :grade_status, :string, default: "pending", null: false
    add_column :scores, :grade_source, :string

    add_index :scores, :pedagogical_grade
    add_index :scores, :grade_status
  end
end
