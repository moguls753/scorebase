class AddSubscriptionFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :stripe_customer_id, :string
    add_column :users, :subscribed_until, :datetime
    add_index :users, :stripe_customer_id, unique: true
  end
end
