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

class LighthouseMilestones < LighthouseAdapter
  
  def initialize(source=nil,credential=nil)
    @fieldset=%w(project-id title due-on)
    
    super(source,credential)
  end
  
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
      # splice in the authentication
      request_url = URI.join("#{base_url[0..6]}#{@source.credential.token}:x@#{base_url[7..-1]}", 
        "/projects/#{project.object}/milestones.xml").to_s
      response = RestClient.get request_url
      
      xml_data = XmlSimple.xml_in(response.to_s); 
      if xml_data["milestone"]
        xml_data["milestone"].each do |milestone|
          @result << milestone
        end
      end
    end

  end
  
  # not planning to create, update or delete milestones on device
end