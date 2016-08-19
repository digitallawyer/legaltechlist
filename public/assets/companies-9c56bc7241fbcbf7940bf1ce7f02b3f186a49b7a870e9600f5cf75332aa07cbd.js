(function() {
  var category, escaped_category, options, sub_category;

  jQuery(function() {});

  $('#companies_sub_category_id').parent().hide();

  sub_category = $('#companies_sub_category_id').html();

  $('#companies_category_id').change(function() {});

  category = $('#companies_category_id :selected').text();

  escaped_category = category.replace(/([ #;&,.+*~\':"!^$[\]()=>|\/@])/g, '\\$1');

  options = $(sub_category).filter("optgroup[label='" + escaped_category + "']").html();

  if (options) {
    $('#companies_sub_category_id').html(options);
    $('#companies_sub_category_id').parent().show();
  } else {
    $('#companies_sub_category_id').empty();
  }

}).call(this);
