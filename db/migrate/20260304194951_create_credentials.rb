class CreateCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :credentials do |t|
      t.string :key, null: false
      t.text :value, null: false
      t.string :description

      t.timestamps
    end

    add_index :credentials, :key, unique: true
  end
end
