class ItemsController < ApplicationController
  def show
    @item = Item.find(params[:id])
    @events = @item.item_events.includes(:pipeline_step).order(created_at: :desc)
  end
end
