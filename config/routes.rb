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
  get 'statistics/tag_distribution', to: 'static_pages#tag_distribution'
  get 'statistics/tag_distribution/download', to: 'static_pages#download_tag_distribution', as: :download_tag_distribution
  get 'statistics/category_evolution', to: 'static_pages#category_evolution'
  get 'statistics/category_evolution/download', to: 'static_pages#download_category_evolution', as: :download_category_evolution
  get 'statistics/total_companies', to: 'static_pages#total_companies'
  get 'statistics/total_companies/download', to: 'static_pages#download_total_companies', as: :download_total_companies
  get 'statistics/funding_concentration', to: 'static_pages#funding_concentration'
  get 'statistics/funding_concentration/download', to: 'static_pages#download_funding_concentration', as: :download_funding_concentration
  get 'statistics/category_success', to: 'static_pages#category_success'
  get 'statistics/category_success/download', to: 'static_pages#download_category_success', as: :download_category_success
  get 'statistics/growth_stage', to: 'static_pages#growth_stage'
  get 'statistics/growth_stage/download', to: 'static_pages#download_growth_stage', as: :download_growth_stage
  get 'statistics/business_model', to: 'static_pages#business_model'
  get 'statistics/business_model/download', to: 'static_pages#download_business_model', as: :download_business_model
  get 'statistics/target_client', to: 'static_pages#target_client'
  get 'statistics/target_client/download', to: 'static_pages#download_target_client', as: :download_target_client
  get 'statistics/country_distribution', to: 'static_pages#country_distribution'
  get 'statistics/country_distribution/download', to: 'static_pages#download_country_distribution', as: :download_country_distribution
  get 'statistics/funding_stages', to: 'static_pages#funding_stages'
  get 'statistics/funding_stages/download', to: 'static_pages#download_funding_stages', as: :download_funding_stages
  get 'statistics/category_maturity', to: 'static_pages#category_maturity'
  get 'statistics/category_maturity/download', to: 'static_pages#download_category_maturity', as: :download_category_maturity
  get 'statistics/funding_efficiency', to: 'static_pages#funding_efficiency'
  get 'statistics/funding_efficiency/download', to: 'static_pages#download_funding_efficiency', as: :download_funding_efficiency
  get 'static_pages/home'
  get 'admin/pieter', to: 'admin/pieter#index'

  # Add tag routes
  get 'tags/:tag', to: 'companies#index', as: :tag
end
