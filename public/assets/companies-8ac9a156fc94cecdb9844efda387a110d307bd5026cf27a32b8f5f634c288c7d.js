jQuery(function() {
  $('#companies_sub_category_id').parent().hide();
  
  var sub_category = $('#companies_sub_category_id').html();
  
  $('#companies_category_id').change(function() {
    var category = $('#companies_category_id :selected').text();
    var escaped_category = category.replace(/([ #;&,.+*~\':"!^$[\]()=>|\/@])/g, '\\$1');
    var options = $(sub_category).filter("optgroup[label='" + escaped_category + "']").html();
    
    if (options) {
      $('#companies_sub_category_id').html(options);
      $('#companies_sub_category_id').parent().show();
    } else {
      $('#companies_sub_category_id').empty();
    }
  });
});
