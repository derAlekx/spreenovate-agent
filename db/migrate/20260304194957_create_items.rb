class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.references :current_step, foreign_key: { to_table: :pipeline_steps }
      t.string :status, null: false, default: "pending"
      t.json :data, null: false, default: {}

      t.timestamps
    end
  end
end
