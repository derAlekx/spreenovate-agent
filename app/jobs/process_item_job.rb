class ProcessItemJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Maximal 5 parallele AI-Calls
  limits_concurrency to: 5, key: "ai_processing"

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
      note: "#{e.class}: #{e.message}"
    )
    Rails.logger.error("ProcessItemJob failed for Item##{item_id}: #{e.class}: #{e.message}")
    raise # Re-raise for retry_on to work
  end
end
