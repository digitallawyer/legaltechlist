module CompaniesHelper
  def tag_links(tags)
    return '' if tags.blank?
    
    tags.split(',').map do |tag|
      tag = tag.strip
      next if tag.blank?
      link_to(tag, companies_path(tag: tag), class: 'tag-link')
    end.compact.join(' ').html_safe
  end
  
  def tag_cloud(tags, classes)
    max = tags.sort_by(&:count).last
    tags.each do |tag|
      index = tag.count.to_f / max.count * (classes.size - 1)
      yield(tag, classes[index.round])
    end
  end
  
  def related_company_list(company)
    @tags = company.all_tags.split(",")
    
    # find all the companies that are tagged
    @companies ||= Array.new
    
    @tags.each do |tag|
      puts "Find tag: #{tag}"
      @found = Company.tagged_with(tag.strip)
      @found.each do |f|
        if f.id != company.id
          @companies.push f
        end
      end
    end
    
    yield(@companies.sort_by(&:name).sample(5))
  end
  
end
