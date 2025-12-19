class CreateDailyStats < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_stats do |t|
      t.date :date
      t.integer :visits, default: 0

      t.timestamps
    end
    add_index :daily_stats, :date, unique: true
  end
end
