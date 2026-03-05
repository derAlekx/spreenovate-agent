class CreateProjectCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :project_credentials do |t|
      t.references :project, null: false, foreign_key: true
      t.references :credential, null: false, foreign_key: true
      t.string :role, null: false

      t.timestamps
    end

    add_index :project_credentials, [:project_id, :role], unique: true
  end
end
