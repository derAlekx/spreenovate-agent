class DashboardController < ApplicationController
  def index
    @projects = Project.all.includes(pipelines: :items)
  end
end
