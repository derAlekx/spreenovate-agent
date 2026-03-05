class CreateItemEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :item_events do |t|
      t.references :item, null: false, foreign_key: true
      t.references :pipeline_step, foreign_key: true
      t.string :event_type, null: false
      t.json :snapshot
      t.text :note

      t.timestamps
    end
  end
end
