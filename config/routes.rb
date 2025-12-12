Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  scope "(:locale)", locale: /en|de/ do
    # Scores
    resources :scores, only: [:index, :show] do
      member do
        get 'file/:file_type', to: 'scores#serve_file', as: 'file'
      end
    end

    # Pages
    get "about", to: "pages#about"
    get "impressum", to: "pages#impressum"

    # Root path
    root "scores#index"
  end
end
