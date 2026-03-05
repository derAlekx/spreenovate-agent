class PipelineStep < ApplicationRecord
  belongs_to :pipeline
  has_many :items, foreign_key: :current_step_id
  has_many :item_events

  validates :name, presence: true
  validates :step_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  VALID_STEP_TYPES = %w[csv_import ai_agent human_review send_email api_pull webhook].freeze
  validates :step_type, inclusion: { in: VALID_STEP_TYPES }
end
