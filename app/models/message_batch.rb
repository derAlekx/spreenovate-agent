class MessageBatch < ApplicationRecord
  belongs_to :pipeline
  belongs_to :pipeline_step

  scope :active, -> { where(status: %w[pending processing]) }

  def ended?
    status == "ended"
  end

  def failed?
    status == "failed"
  end

  def items
    Item.where(id: item_ids)
  end
end
