# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

jQuery -> 

$('#companies_sub_category_id').parent().hide()

sub_category = $('#companies_sub_category_id').html()

$('#companies_category_id').change ->

category = $('#companies_category_id :selected').text()

escaped_category = category.replace(/([ #;&,.+*~\':"!^$[\]()=>|\/@])/g, '\\$1')

options = $(sub_category).filter("optgroup[label='#{escaped_category}']").html()

if options
	$('#companies_sub_category_id').html(options)
	$('#companies_sub_category_id').parent().show()
else
	$('#companies_sub_category_id').empty()
