#
# Author: Vidal Graupera
#
# Example REST source adapter using http://lighthouseapp.com/api/milestones
#
# <milestone>
#   <created-at type="datetime">2006-11-07T22:53:25Z</created-at>
#   <due-on type="datetime">2007-04-30T20:30:00Z</due-on>
#   <goals>#{unprocessed body}</goals>
#   <goals-html>#{processed HTML body}</goals-html>
#   <id type="integer">1</id>
#   <open-tickets-count type="integer">17</open-tickets-count>
#   <permalink>emergence-day</permalink>
#   <project-id type="integer">2</project-id>
#   <tickets-count type="integer">55</tickets-count>
#   <title>Emergence Day</title>
# </milestone>
# 


class LighthouseMilestones < SourceAdapter
  
  include RestAPIHelpers

  def query
    log "LighthouseMilestones query"
        
    # iterate over all projects/<id>/Memberships.xml to get user ids
    # we use the IDs of the projects already synced in LighthouseProjects adapter
    projectSource = Source.find_by_adapter("LighthouseProjects")
    projects = ObjectValue.find(:all, :conditions => {
      :source_id => projectSource.id, :update_type => 'query',
      :attrib => 'name', :user_id=>@source.current_user.id})
        
    @result = []
      
    projects.each do |project|  
      uri = URI.parse(base_url)
      url = "/projects/#{project.object}/milestones.xml"
      req = Net::HTTP::Get.new(url, 'Accept' => 'application/xml')      
      req.basic_auth @source.credential.token, "x"

      response = Net::HTTP.start(uri.host,uri.port) do |http|
        http.set_debug_output $stderr
        http.request(req)
      end
      xml_data = XmlSimple.xml_in(response.body); 

      if xml_data["milestone"]
        xml_data["milestone"].each do |milestone|
          @result << milestone
        end
      end
    end

  end

  def sync
    if @result
      log "LighthouseMilestones sync, with #{@result.length} results"
    else
      log "LighthouseMilestones sync, ERROR @result nil"
      return
    end
        
    @result.each do |milestone|      
      id = milestone["id"][0]["content"]
      
      # iterate over all possible values, if the value is not found we just pass "" in to rhosync
      %w(project-id title due-on).each do |key|
        value = milestone[key] ? milestone[key][0] : ""
        add_triple(@source.id, id, key.gsub('-','_'), value, @source.current_user.id)
        # convert "-" to "_" because "-" is not valid in ruby variable names   
      end
    end
  end
  
  # not planning to create, update or delete milestones on device
end