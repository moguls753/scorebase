Rails.application.routes.draw do
  resource :session
  resource :user, only: %i[new create]
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Redirect /en/* to /* (English is default, no prefix needed)
  get "/en/*path", to: redirect("/%{path}", status: 301)
  get "/en", to: redirect("/", status: 301)

  scope "(:locale)", locale: /de/ do
    # Pro Landing Page - canonical URL for SEO
    get "smart-search", to: "pages#pro", as: :pro_landing

    # Short redirect for branding
    get "pro", to: redirect { |params, request|
      params[:locale] ? "/#{params[:locale]}/smart-search" : "/smart-search"
    }

    # Smart Search Feature (actual tool - will be gated behind auth when ready)
    get "search/ai", to: "scores#smart_search", as: :smart_search

    # Scores
    resources :scores, only: [:index, :show] do
      member do
        get "file/:file_type", to: "scores#serve_file", as: "file"
      end
    end

    # Hub/Landing Pages (SEO vanity pages)
    # Single dimension
    get "composers", to: "hub_pages#composers_index", as: :composers
    get "composers/:slug", to: "hub_pages#composer", as: :composer
    get "genres", to: "hub_pages#genres_index", as: :genres
    get "genres/:slug", to: "hub_pages#genre", as: :genre
    get "instruments", to: "hub_pages#instruments_index", as: :instruments
    get "instruments/:slug", to: "hub_pages#instrument", as: :instrument
    get "periods", to: "hub_pages#periods_index", as: :periods
    get "periods/:slug", to: "hub_pages#period", as: :period

    # Combined pages (Tier 1 combinations)
    get "composers/:composer_slug/:instrument_slug", to: "hub_pages#composer_instrument", as: :composer_instrument
    get "genres/:genre_slug/:instrument_slug", to: "hub_pages#genre_instrument", as: :genre_instrument

    # Pages
    get "about", to: "pages#about"
    get "impressum", to: "pages#impressum"

    # Root path
    root "scores#index"
  end
end
