# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

target_clients = TargetClient.create([
  {name: "Law Firms", description: "Products and services for law firms and legal practices"},
  {name: "Corporate Legal", description: "Solutions for in-house legal departments and corporate counsel"},
  {name: "Government", description: "Services for government legal departments and agencies"},
  {name: "Individual Consumers", description: "Direct-to-consumer legal solutions and services"},
  {name: "Legal Education", description: "Tools for law schools, continuing education, and training"},
  {name: "Legal Service Providers", description: "Solutions for alternative legal service providers and legal tech companies"}
])

business_model = BusinessModel.create([
  {name: "SaaS", description: "Software as a Service - subscription-based software products"},
  {name: "Marketplace", description: "Platform connecting legal service providers with clients"},
  {name: "Data & Analytics", description: "Legal data, research, and analytics services"},
  {name: "Managed Service", description: "Technology-enabled legal services with human support"},
  {name: "Content Provider", description: "Legal content, forms, and document providers"}
])

# Only create admin if it doesn't exist
unless AdminUser.exists?(email: 'admin@example.com')
  AdminUser.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password')
end
