class UpdateCompanyCategoriesAndRemoveUnused < ActiveRecord::Migration[7.0]
  def up
    # First, update all companies to their new categories
    {
      'Collaboration & Communication' => 'Practice Management',
      'Online Portals' => 'Marketplace and ALSPs',
      'Consulting' => 'Analytics & Insights',
      'Business Process Automation' => 'Analytics & Insights',
      'Developer Tools' => 'Document Management and Automation'
    }.each do |old_name, new_name|
      execute <<-SQL
        UPDATE companies
        SET category_id = (SELECT id FROM categories WHERE name = '#{new_name}')
        WHERE category_id = (SELECT id FROM categories WHERE name = '#{old_name}');
      SQL
    end

    # Now we can safely remove the old categories
    old_categories = [
      'Collaboration & Communication',
      'Online Portals',
      'Consulting',
      'Business Process Automation',
      'Developer Tools'
    ]

    # Delete the categories now that no companies reference them
    Category.where(name: old_categories).destroy_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
