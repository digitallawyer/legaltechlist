class RecategorizeAndRemoveOldCategories < ActiveRecord::Migration[7.0]
  def up
    # Get the target categories
    practice_mgmt = Category.find_by!(name: "Practice Management")
    marketplace = Category.find_by!(name: "Marketplace and ALSPs")
    analytics = Category.find_by!(name: "Analytics & Insights")
    doc_mgmt = Category.find_by!(name: "Document Management and Automation")

    # Update companies to new categories
    execute <<-SQL
      UPDATE companies
      SET category_id = #{practice_mgmt.id}
      WHERE id IN (300, 9779);

      UPDATE companies
      SET category_id = #{marketplace.id}
      WHERE id IN (390, 9869, 10868);

      UPDATE companies
      SET category_id = #{analytics.id}
      WHERE id IN (1389, 1726, 11204);

      UPDATE companies
      SET category_id = #{doc_mgmt.id}
      WHERE id IN (1744, 11222);
    SQL

    # Remove old categories
    old_categories = [
      "Collaboration & Communication",
      "Online Portals",
      "Consulting",
      "Business Process Automation",
      "Developer Tools"
    ]

    Category.where(name: old_categories).destroy_all
  end

  def down
    # This migration cannot be reversed as it would require knowing the original categories
    # of each company
    raise ActiveRecord::IrreversibleMigration
  end
end
