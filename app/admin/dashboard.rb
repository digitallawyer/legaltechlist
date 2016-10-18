ActiveAdmin.register_page "Dashboard" do

  menu priority: 1, label: proc{ I18n.t("active_admin.dashboard") }

  content title: proc{ I18n.t("active_admin.dashboard") } do
    #div class: "blank_slate_container", id: "dashboard_default_message" do
    #  span class: "blank_slate" do
    #    span I18n.t("active_admin.dashboard_welcome.welcome")
    #    small I18n.t("active_admin.dashboard_welcome.call_to_action")
    #  end
    #end

    # Here is an example of a simple dashboard with columns and panels.
    #
    columns do
       column do
         panel "Export Database" do
           ul do
             link_to("Download CSV - Companies", "companies/export_csv")
           end
           ul do
             link_to("Upload CSV - Companies", "companies/upload_csv")
           end
         end
       end

       column do
         panel "Info" do
           para "Welcome to the administrator interface for the legal tech list database."
         end
       end
     end
  end # content
end
