Rails.application.routes.draw do
  root "projects#index"

  resources :credentials, except: [:show]

  resources :projects, only: [:index, :show] do
    collection do
      get  "wizard",        to: "project_wizard#step1", as: :wizard
      post "wizard/step1",  to: "project_wizard#save_step1", as: :wizard_save_step1
      get  "wizard/step2",  to: "project_wizard#step2", as: :wizard_step2
      post "wizard/step2",  to: "project_wizard#save_step2", as: :wizard_save_step2
      get  "wizard/step3",  to: "project_wizard#step3", as: :wizard_step3
      post "wizard/step3",  to: "project_wizard#save_step3", as: :wizard_save_step3
      get  "wizard/step4",  to: "project_wizard#step4", as: :wizard_step4
      post "wizard/finish", to: "project_wizard#finish", as: :wizard_finish
      delete "wizard",      to: "project_wizard#cancel", as: :wizard_cancel
    end
  end

  resources :pipelines, only: [:show] do
    member do
      post :import_csv
      post :bulk_send
      post :test_send
      patch :update_daily_limit
    end
    resources :items, only: [:show, :update], controller: "pipeline_items" do
      member do
        post :approve
        post :skip
        post :reset
        post :retry
        post :redraft
        post :send_email
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
