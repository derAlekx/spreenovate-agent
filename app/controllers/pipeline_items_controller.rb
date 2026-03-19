class PipelineItemsController < ApplicationController
  before_action :set_pipeline
  before_action :set_item, only: [:show, :update, :approve, :skip, :reset, :retry, :redraft, :send_email, :process_item]

  def show
    redirect_to pipeline_path(@pipeline, anchor: dom_id(@item))
  end

  def approve
    review_step = @item.current_step
    @item.update!(status: "approved")
    @item.item_events.create!(
      pipeline_step: review_step,
      event_type: "human_approved"
    )
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def skip
    review_step = @item.current_step
    @item.update!(status: "rejected")
    @item.item_events.create!(
      pipeline_step: review_step,
      event_type: "human_rejected",
      note: params[:reason]
    )
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def reset
    @item.update!(status: "review")
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def retry
    @item.update!(status: "pending")
    ProcessItemJob.perform_later(@item.id)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline), notice: "Item wird erneut verarbeitet." }
    end
  end

  def redraft
    draft_step = @pipeline.pipeline_steps.find_by(step_type: "ai_agent", config: PipelineStep.arel_table[:config].matches('%"task":"draft"%'))
    draft_step ||= @pipeline.pipeline_steps.find_by(name: "Draft")

    @item.update!(status: "processing", current_step: draft_step)
    RedraftJob.perform_later(@item.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline), notice: "Neue Version wird erstellt..." }
    end
  end

  def update
    data = @item.data.dup
    data["draft"] ||= {}
    data["draft"]["subject"] = params[:subject] if params[:subject]
    data["draft"]["body"] = params[:body] if params[:body]
    @item.update!(data: data)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline) }
    end
  end

  def send_email
    send_step = @pipeline.pipeline_steps.find_by(step_type: "send_email")

    unless @item.status == "approved"
      redirect_to pipeline_path(@pipeline), alert: "Nur approved Items können gesendet werden."
      return
    end

    if @pipeline.remaining_sends_today <= 0
      redirect_to pipeline_path(@pipeline), alert: "Tageslimit erreicht (#{@pipeline.daily_limit}/#{@pipeline.daily_limit})."
      return
    end

    @item.update!(current_step: send_step)
    ProcessItemJob.perform_later(@item.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline), notice: "Email wird gesendet..." }
    end
  end

  def process_item
    unless @item.status == "pending"
      redirect_to pipeline_path(@pipeline), alert: "Nur pending Items können gestartet werden."
      return
    end

    @item.update!(status: "processing")
    ProcessItemJob.perform_later(@item.id)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pipeline_path(@pipeline), notice: "Item wird verarbeitet..." }
    end
  end

  def bulk_process
    batch_size = (params[:batch_size] || 50).to_i
    items = @pipeline.items.where(status: "pending").limit(batch_size)
    count = 0

    items.find_each do |item|
      ProcessItemJob.perform_later(item.id)
      count += 1
    end

    redirect_to pipeline_path(@pipeline, filter: params[:filter]),
      notice: "#{count} Items werden verarbeitet..."
  end

  def bulk_approve
    items = @pipeline.items.where(status: "review")
    review_step = @pipeline.pipeline_steps.find_by(step_type: "human_review")

    items.find_each do |item|
      item.update!(status: "approved")
      item.item_events.create!(
        pipeline_step: review_step,
        event_type: "human_approved",
        note: "Bulk approved"
      )
    end

    redirect_to pipeline_path(@pipeline, filter: params[:filter]),
      notice: "#{items.count} Items approved."
  end

  def bulk_reset
    items = @pipeline.items.where(status: %w[approved rejected])

    items.update_all(status: "review")

    redirect_to pipeline_path(@pipeline, filter: params[:filter]),
      notice: "#{items.count} Items zurückgesetzt."
  end

  private

  def set_pipeline
    @pipeline = Pipeline.find(params[:pipeline_id])
  end

  def set_item
    @item = @pipeline.items.find(params[:id])
  end
end
