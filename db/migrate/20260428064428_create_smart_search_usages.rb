class CreateSmartSearchUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :smart_search_usages do |t|
      t.date    :date,  null: false, index: { unique: true }
      t.integer :count, null: false, default: 0

      t.timestamps
    end
  end
end
