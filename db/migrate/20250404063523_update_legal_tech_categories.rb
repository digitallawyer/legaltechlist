class UpdateLegalTechCategories < ActiveRecord::Migration[7.0]
  def up
    # Remove unwanted categories
    categories_to_remove = [
      'Collaboration & Communication',
      'Online Portals',
      'Consulting',
      'Business Process Automation',
      'Developer Tools'
    ]

    categories_to_remove.each do |name|
      cat = Category.find_by(name: name)
      if cat
        # Move any companies to "Unknown" category
        unknown = Category.find_or_create_by!(name: 'Unknown')
        Company.where(category_id: cat.id).update_all(category_id: unknown.id)
        # Delete the category
        cat.destroy
      end
    end
  end

  def down
    # No need to recreate these categories
  end
end
