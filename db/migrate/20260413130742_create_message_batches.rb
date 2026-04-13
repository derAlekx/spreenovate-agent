class CreateMessageBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :message_batches do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.references :pipeline_step, null: false, foreign_key: true
      t.string :batch_api_id
      t.string :status
      t.integer :request_count, default: 0
      t.integer :succeeded_count, default: 0
      t.integer :failed_count, default: 0
      t.json :item_ids

      t.timestamps
    end
  end
end
