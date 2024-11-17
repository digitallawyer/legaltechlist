Rails.application.routes.draw do
  # Admin and Authentication
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  
  # Resources
  resources :companies
  root to: 'static_pages#home'

  # Company filters
  get 'categories/:category' => 'companies#index', as: :category
  get 'business_models/:business_model' => 'companies#index', as: :business_model
  get 'target_clients/:target_client' => 'companies#index', as: :target_client
  
  # Company views
  get 'feed', to: 'companies#feed'
  get 'map', to: 'companies#map'
  
  # Static pages
  get 'about', to: 'static_pages#about'
  get 'statistics', to: 'static_pages#statistics'
  get 'static_pages/home'
  get 'admin/pieter', to: 'admin/pieter#index'
  
  # Add tag routes
  get 'tags/:tag', to: 'companies#index', as: :tag
end
