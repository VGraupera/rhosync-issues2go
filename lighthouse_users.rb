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
    
    # iterate over all tickets and make sure we have user info for each
    tickets_src = Source.find_by_adapter("LighthouseTickets")
    
    unique_users =  ObjectValue.find(:all, :select => "distinct(value)",
    :conditions => ["source_id = ? and update_type = 'query' and user_id = ? and 
      (attrib = 'user_id' OR attrib = 'assigned_user_id' OR attrib = 'creator_id')",
      tickets_src.id, @source.current_user.id])
      
    log "unique_users count=#{unique_users.length}"
      
    @result = []
    unique_users.each do |user|
      uri = URI.parse(base_url)
      req = Net::HTTP::Get.new("/users/#{user.value}.xml", 'Accept' => 'application/xml')
      req.basic_auth @source.credential.token, "x"
      response = Net::HTTP.start(uri.host,uri.port) do |http|
        http.set_debug_output $stderr
        http.request(req)
      end
      xml_data = XmlSimple.xml_in(response.body);
      
      if xml_data && xml_data.class != String
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