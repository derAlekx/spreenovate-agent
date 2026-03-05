class PipelineItemsController < ApplicationController
  before_action :set_pipeline
  before_action :set_item, only: [:show, :update, :approve, :skip, :reset, :retry]

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
