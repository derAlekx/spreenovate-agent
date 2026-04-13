# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_13_130742) do
  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value", null: false
    t.index ["key"], name: "index_credentials_on_key", unique: true
  end

  create_table "item_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.integer "item_id", null: false
    t.text "note"
    t.integer "pipeline_step_id"
    t.json "snapshot"
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_item_events_on_item_id"
    t.index ["pipeline_step_id"], name: "index_item_events_on_pipeline_step_id"
  end

  create_table "items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_step_id"
    t.json "data", default: {}, null: false
    t.integer "pipeline_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index "json_extract(data, '$.company')", name: "idx_items_company", where: "json_extract(data, '$.company') IS NOT NULL"
    t.index "pipeline_id, json_extract(data, '$.email')", name: "idx_items_pipeline_email", unique: true, where: "json_extract(data, '$.email') IS NOT NULL"
    t.index ["current_step_id"], name: "index_items_on_current_step_id"
    t.index ["pipeline_id", "status"], name: "idx_items_pipeline_status"
    t.index ["pipeline_id"], name: "index_items_on_pipeline_id"
  end

  create_table "message_batches", force: :cascade do |t|
    t.string "batch_api_id"
    t.datetime "created_at", null: false
    t.integer "failed_count", default: 0
    t.json "item_ids"
    t.integer "pipeline_id", null: false
    t.integer "pipeline_step_id", null: false
    t.integer "request_count", default: 0
    t.string "status"
    t.integer "succeeded_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["pipeline_id"], name: "index_message_batches_on_pipeline_id"
    t.index ["pipeline_step_id"], name: "index_message_batches_on_pipeline_step_id"
  end

  create_table "pipeline_steps", force: :cascade do |t|
    t.json "config"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "pipeline_id", null: false
    t.integer "position", null: false
    t.string "step_type", null: false
    t.datetime "updated_at", null: false
    t.index ["pipeline_id"], name: "index_pipeline_steps_on_pipeline_id"
  end

  create_table "pipelines", force: :cascade do |t|
    t.json "config"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_pipelines_on_project_id"
  end

  create_table "project_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "credential_id", null: false
    t.integer "project_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["credential_id"], name: "index_project_credentials_on_credential_id"
    t.index ["project_id", "role"], name: "index_project_credentials_on_project_id_and_role", unique: true
    t.index ["project_id"], name: "index_project_credentials_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.json "settings"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "item_events", "items"
  add_foreign_key "item_events", "pipeline_steps"
  add_foreign_key "items", "pipeline_steps", column: "current_step_id"
  add_foreign_key "items", "pipelines"
  add_foreign_key "message_batches", "pipeline_steps"
  add_foreign_key "message_batches", "pipelines"
  add_foreign_key "pipeline_steps", "pipelines"
  add_foreign_key "pipelines", "projects"
  add_foreign_key "project_credentials", "credentials"
  add_foreign_key "project_credentials", "projects"
end
