class CreatePipelineSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :pipeline_steps do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.string :step_type, null: false
      t.integer :position, null: false
      t.json :config

      t.timestamps
    end
  end
end
