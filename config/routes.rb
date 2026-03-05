Rails.application.routes.draw do
  root "projects#index"

  resources :projects, only: [:index, :show]

  resources :pipelines, only: [:show] do
    member do
      post :import_csv
    end
    resources :items, only: [:show, :update], controller: "pipeline_items" do
      member do
        post :approve
        post :skip
        post :reset
        post :retry
      end
      collection do
        post :bulk_approve
        post :bulk_reset
      end
    end
  end

  resources :items, only: [:show]

  get "up" => "rails/health#show", as: :rails_health_check
end
