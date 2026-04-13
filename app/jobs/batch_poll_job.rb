class BatchPollJob < ApplicationJob
  queue_as :default

  MAX_POLLS = 800 # ~26 hours at 2min intervals

  def perform(message_batch_id, poll_count = 0)
    message_batch = MessageBatch.find(message_batch_id)
    return if message_batch.ended? || message_batch.failed?

    project = message_batch.pipeline.project
    api_key = project.credential_for("ai_api_key")
    client = ClaudeClient.new(api_key: api_key)

    # Check batch status (rescue transient network errors)
    begin
      batch_status = client.get_batch(batch_id: message_batch.batch_api_id)
    rescue => e
      Rails.logger.warn("BatchPollJob: Network error checking batch #{message_batch.batch_api_id}: #{e.message}")
      if poll_count + 1 >= MAX_POLLS
        mark_timed_out(message_batch)
      else
        BatchPollJob.set(wait: 2.minutes).perform_later(message_batch_id, poll_count + 1)
      end
      return
    end

    processing_status = batch_status["processing_status"]
    Rails.logger.info("BatchPollJob: Batch #{message_batch.batch_api_id} status=#{processing_status} (poll #{poll_count + 1}/#{MAX_POLLS})")

    if processing_status == "ended"
      process_results(message_batch, client)
    elsif poll_count + 1 >= MAX_POLLS
      mark_timed_out(message_batch)
    else
      BatchPollJob.set(wait: 2.minutes).perform_later(message_batch_id, poll_count + 1)
    end
  end

  private

  def process_results(message_batch, client)
    results = client.get_batch_results(batch_id: message_batch.batch_api_id)
    step = message_batch.pipeline_step
    pipeline = message_batch.pipeline

    succeeded = 0
    failed = 0
    succeeded_item_ids = []

    results.each do |result|
      item_id = result["custom_id"].to_i
      item = Item.find_by(id: item_id)
      next unless item

      begin
        StepExecutors::AiAgent.apply_batch_result(item, step, result)
        if result.dig("result", "type") == "succeeded"
          succeeded += 1
          succeeded_item_ids << item.id
        else
          failed += 1
        end
      rescue => e
        failed += 1
        Rails.logger.error("BatchPollJob: Failed to apply result for Item##{item_id}: #{e.class}: #{e.message}")
        item.update!(status: "failed")
        item.item_events.create!(
          pipeline_step: step,
          event_type: "error",
          note: "Batch result error: #{e.class}: #{e.message}"
        )
      end
    end

    message_batch.update!(
      status: "ended",
      succeeded_count: succeeded,
      failed_count: failed
    )

    Rails.logger.info("BatchPollJob: Batch #{message_batch.batch_api_id} completed. #{succeeded} succeeded, #{failed} failed.")

    # Cascade: if next step is also an AI step, auto-submit the next batch
    cascade_to_next_step(pipeline, step, succeeded_item_ids) if succeeded_item_ids.any?
  end

  def cascade_to_next_step(pipeline, current_step, item_ids)
    steps = pipeline.pipeline_steps.order(:position)
    current_index = steps.index(current_step)
    next_step = steps[current_index + 1] if current_index

    return unless next_step
    return unless next_step.step_type == "ai_agent"

    # Items were already moved to next_step with status "pending" by apply_batch_result
    # Capture IDs before update_all (the relation has status: "pending" in WHERE)
    cascade_ids = pipeline.items.where(id: item_ids, current_step_id: next_step.id, status: "pending").pluck(:id)
    return if cascade_ids.empty?

    Item.where(id: cascade_ids).update_all(status: "processing")
    BatchSubmitJob.perform_later(pipeline.id, next_step.id, cascade_ids)

    Rails.logger.info("BatchPollJob: Cascading #{cascade_ids.size} items to step '#{next_step.name}'")
  end

  def mark_timed_out(message_batch)
    message_batch.update!(status: "failed")
    # Reset stuck items to failed so they can be retried
    Item.where(id: message_batch.item_ids, status: "processing").update_all(status: "failed")
    Rails.logger.error("BatchPollJob: Batch #{message_batch.batch_api_id} timed out after #{MAX_POLLS} polls. Items set to failed.")
  end
end
