class ProcessItemJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    step = item.current_step

    return unless step

    executor = StepExecutors.for(step.step_type).new(item, step)
    executor.execute
  rescue => e
    item.update!(status: "failed")
    item.item_events.create!(
      pipeline_step: item.current_step,
      event_type: "error",
      note: e.message
    )
    Rails.logger.error("ProcessItemJob failed for Item##{item_id}: #{e.message}")
  end
end
