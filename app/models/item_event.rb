class ItemEvent < ApplicationRecord
  belongs_to :item
  belongs_to :pipeline_step, optional: true

  validates :event_type, presence: true
end
