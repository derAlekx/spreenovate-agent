class Item < ApplicationRecord
  belongs_to :pipeline
  belongs_to :current_step, class_name: "PipelineStep", optional: true
  has_many :item_events, dependent: :destroy

  validates :status, presence: true

  VALID_STATUSES = %w[pending processing review done approved rejected failed sent excluded].freeze
  validates :status, inclusion: { in: VALID_STATUSES }

  scope :by_email, ->(email) { where("json_extract(data, '$.email') = ?", email) }
  scope :by_company, ->(company) { where("json_extract(data, '$.company') = ?", company) }
  scope :pending, -> { where(status: "pending") }
  scope :for_review, -> { where(status: "review") }
  scope :approved, -> { where(status: "approved") }

  def advance_to_next_step!
    steps = pipeline.pipeline_steps.order(:position)
    current_index = steps.index(current_step)
    next_step = steps[current_index + 1] if current_index
    if next_step
      if next_step.step_type == "human_review"
        # Human Review: Status direkt auf "review" setzen
        update!(current_step: next_step, status: "review")
      else
        update!(current_step: next_step, status: "pending")
        ProcessItemJob.perform_later(id)
      end
    else
      update!(current_step: nil, status: "done")
    end
  end
end
