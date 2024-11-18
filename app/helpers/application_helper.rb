module ApplicationHelper
  def category_icon(category_name)
    case category_name.downcase
    when /analytics/ then 'fa fa-chart-bar'
    when /compliance/ then 'fa fa-shield'
    when /contract/ then 'fa fa-file-contract'
    when /document/ then 'fa fa-folder'
    when /research/ then 'fa fa-book'
    when /litigation/ then 'fa fa-scale-balanced'
    when /operations/ then 'fa fa-building'
    when /collaboration/ then 'fa fa-users'
    when /ai|emerging/ then 'fa fa-microchip'
    when /talent|people/ then 'fa fa-user-plus'
    when /marketplace/ then 'fa fa-briefcase'
    when /ip|intellectual/ then 'fa fa-lightbulb'
    when /process/ then 'fa fa-gears'
    when /dei|diversity/ then 'fa fa-users-between-lines'
    when /security/ then 'fa fa-lock'
    else 'fa fa-cube'
    end
  end
end
