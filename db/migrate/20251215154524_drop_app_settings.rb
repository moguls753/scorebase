class DropAppSettings < ActiveRecord::Migration[8.1]
  def up
    drop_table :app_settings
  end

  def down
    create_table :app_settings do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :app_settings, :key, unique: true
  end
end
