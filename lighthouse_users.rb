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

class LighthouseUsers < LighthouseAdapter

  def initialize(source=nil,credential=nil)
    @fieldset=%w(job name website)
    
    super(source,credential)
  end
  
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
      # splice in the authentication
      request_url = URI.join("#{base_url[0..6]}#{@source.credential.token}:x@#{base_url[7..-1]}", "users/#{user.value}.xml").to_s
      response = RestClient.get request_url
      xml_data = XmlSimple.xml_in(response.to_s);
      if xml_data && xml_data.class != String
        @result << xml_data
      end
    end
    
  end
  
  # not planning to create, update or delete users on device
end