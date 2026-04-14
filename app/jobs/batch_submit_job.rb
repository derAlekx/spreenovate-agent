class BatchSubmitJob < ApplicationJob
  queue_as :default

  def perform(pipeline_id, step_id, item_ids)
    pipeline = Pipeline.find(pipeline_id)
    step = PipelineStep.find(step_id)
    project = pipeline.project
    api_key = project.credential_for("ai_api_key")

    raise "Kein API Key für Projekt #{project.name}" unless api_key

    # Items are already "processing" (set by controller or cascade)
    items = pipeline.items.where(id: item_ids, current_step_id: step_id)
    return if items.empty?

    # Build batch requests (draft step returns 2 per item for A/B)
    requests = items.flat_map do |item|
      StepExecutors::AiAgent.build_batch_requests(item, step)
    end

    # Create tracking record BEFORE submitting to API
    message_batch = MessageBatch.create!(
      pipeline: pipeline,
      pipeline_step: step,
      batch_api_id: nil,
      status: "pending",
      request_count: items.count,
      item_ids: items.pluck(:id)
    )

    # Submit batch to Claude
    begin
      response = ClaudeClient.new(api_key: api_key).create_batch(requests: requests)
      message_batch.update!(batch_api_id: response["id"], status: "processing")
      Rails.logger.info("BatchSubmitJob: Submitted batch #{response['id']} with #{items.count} items")
    rescue => e
      message_batch.update!(status: "failed")
      items.update_all(status: "failed")
      Rails.logger.error("BatchSubmitJob: Failed to submit batch: #{e.class}: #{e.message}")
      raise
    end

    # Start polling
    BatchPollJob.set(wait: 30.seconds).perform_later(message_batch.id)
  end
end
