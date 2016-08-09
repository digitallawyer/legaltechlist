# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

target_clients = TargetClient.create([
  {name:"Unknown",     description:"Business Model Not Known."},
  {name:"Individuals", description:"Serves Individuals Directly."},
  {name:"Companies",   description:"Serves Companies Directly."},
  {name:"Government",  description:"Serves Governmnet Directly."},
  {name:"Service Providers", description:"Serves Lawyers, Law Firms, and Other Legal Service Providers."}
])

business_model = BusinessModel.create([
  {name:"Unknown", description:"Business Model not known"},
  {name:"Legal Tech", description:"Creates and Sells Technology Products."},
  {name:"Legal Service Using Tech", description:"Provides a legal service using legal tech."}
])

AdminUser.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password')