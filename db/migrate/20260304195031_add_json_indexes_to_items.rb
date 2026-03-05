class AddJsonIndexesToItems < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE UNIQUE INDEX idx_items_pipeline_email
        ON items(pipeline_id, json_extract(data, '$.email'))
        WHERE json_extract(data, '$.email') IS NOT NULL;
    SQL

    execute <<~SQL
      CREATE INDEX idx_items_company
        ON items(json_extract(data, '$.company'))
        WHERE json_extract(data, '$.company') IS NOT NULL;
    SQL

    execute <<~SQL
      CREATE INDEX idx_items_pipeline_status
        ON items(pipeline_id, status);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_items_pipeline_email"
    execute "DROP INDEX IF EXISTS idx_items_company"
    execute "DROP INDEX IF EXISTS idx_items_pipeline_status"
  end
end
