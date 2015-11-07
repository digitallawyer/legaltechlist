# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

categories = Category.create([
  {name:'Uncategorized', description:'No category set.'},
  {name:'Case Management'}, 
  {name:'Document Automation'}, 
  {name:'Estates and Wills'}, 
  {name:'Lawyer Marketplace'},
  {name:'Lawyer Matching'},
  {name:'Lawyer Referrals Network'}
  ])