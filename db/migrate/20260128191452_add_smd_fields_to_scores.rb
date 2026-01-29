class AddSmdFieldsToScores < ActiveRecord::Migration[8.1]
  def change
    # SMD-specific fields (nil for other sources)
    #
    # NOTE: SMD "genres" (Pop, Rock, Broadway, etc.) go into existing `tags` field.
    # ScoreBase `genre` field stores musical FORM (Fugue, Sonata, Mass).
    # TODO: Consider renaming `genre` → `form` and adding proper `genre` field
    #       for style categories (Jazz, Pop, Classical, etc.)

    # Core
    add_column :scores, :clean_title, :string
    add_column :scores, :contributors, :json
    add_column :scores, :main_instrument, :string

    # Classification
    add_column :scores, :arrangement_category, :string
    add_column :scores, :smd_category, :string

    # Publisher
    add_column :scores, :brand, :string
    add_column :scores, :is_arrangeme, :boolean

    # Pricing
    add_column :scores, :price_usd, :decimal, precision: 8, scale: 2
    add_column :scores, :original_price_usd, :decimal, precision: 8, scale: 2

    # Reviews
    add_column :scores, :review_count, :integer

    # Details
    add_column :scores, :pitch_range, :string
    add_column :scores, :is_interactive, :boolean

    # Images
    add_column :scores, :preview_image_url, :string

    # Indexes for filtering/sorting
    add_index :scores, :brand
    add_index :scores, :is_arrangeme
    add_index :scores, :price_usd
  end
end
