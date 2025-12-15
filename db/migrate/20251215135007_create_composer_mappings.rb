class CreateComposerMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :composer_mappings do |t|
      t.string :original_name, null: false
      t.string :normalized_name  # nil = "tried but couldn't normalize"
      t.string :source  # imslp_priority, gemini, groq, manual, cpdl, pdmx
      t.boolean :verified, default: false, null: false

      t.timestamps
    end

    add_index :composer_mappings, :original_name, unique: true
    add_index :composer_mappings, :normalized_name
  end
end
