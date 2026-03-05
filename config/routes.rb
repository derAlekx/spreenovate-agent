Rails.application.routes.draw do
  root "projects#index"

  resources :projects, only: [:index, :show]

  resources :pipelines, only: [:show] do
    member do
      post :import_csv
    end
  end

  resources :items, only: [:show]

  get "up" => "rails/health#show", as: :rails_health_check
end
