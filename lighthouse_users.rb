#
# Author: Vidal Graupera
#
# Example REST source adapter using http://lighthouseapp.com/api/users
#
# <user>Subscription
#   <id type="integer">1</id>
#   <job>Rails Monkey</job>
#   <name>rick</name>
#   <website></website>
# </user>


class LighthouseUsers < SourceAdapter
  
  include RestAPIHelpers

  def query
    log "LighthouseUsers query"
    
    user_ids = []
    
    # iterate over all projects/<id>/memberships.xml to get user ids
    # we use the IDs of the projects already synced in LighthouseProjects adapter
    projectSource = Source.find_by_adapter("LighthouseProjects")
    
    projects = ObjectValue.find(:all, :conditions => {
      :source_id => projectSource.id, :update_type => 'query',
      :attrib => 'name', :user_id=>@source.current_user.id})
      
    log "projects count=#{projects.length}"
      
    projects.each do |project|
      uri = URI.parse(base_url)
      url = "/projects/#{project.object}/memberships.xml"
      req = Net::HTTP::Get.new(url, 'Accept' => 'application/xml')      
      req.basic_auth @source.credential.token, "x"

      response = Net::HTTP.start(uri.host,uri.port) do |http|
        http.set_debug_output $stderr
        http.request(req)
      end
      xml_data = XmlSimple.xml_in(response.body); 

      # <memberships type="array">
      #   <membership>
      #     <id type="integer">8666</id>
      #     <user-id type="integer">9435</user-id>
      #     <account>http://vdggroup.lighthouseapp.com</account>
      #   </membership>
      # </memberships>
      #
            
      # if there are no memberships for a project this will be nil
      if xml_data["membership"]
        xml_data["membership"].each do |membership|
          user_ids << membership["user-id"][0]["content"]
        end
      end
    end
    
    user_ids.uniq! 
    
    @result = []
    
    #then for each one - GET /users/#{ID}.xml
    user_ids.each do |user_id|
      uri = URI.parse(base_url)
      req = Net::HTTP::Get.new("/users/#{user_id}.xml", 'Accept' => 'application/xml')
      req.basic_auth @source.credential.token, "x"
      response = Net::HTTP.start(uri.host,uri.port) do |http|
        http.set_debug_output $stderr
        http.request(req)
      end
      xml_data = XmlSimple.xml_in(response.body);
      
      if xml_data
        @result << xml_data
      end
    end
  end

  def sync
    if @result
      log "LighthouseUsers sync, with #{@result.length} results"
    else
      log "LighthouseUsers sync, ERROR @result nil"
      return
    end
    
    @result.each do |user|
      id = user["id"][0]["content"]
      
      # iterate over all possible values, if the value is not found we just pass "" in to rhosync
      %w(job name website).each do |key|
        value = user[key] ? user[key][0] : ""
        add_triple(@source.id, id, key.gsub('-','_'), value, @source.current_user.id)
        # convert "-" to "_" because "-" is not valid in ruby variable names   
      end
    end
  end
  
  # not planning to create, update or delete users on device
end