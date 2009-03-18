#
# Author: Vidal Graupera
#
# Example REST source adapter using http://lighthouseapp.com/api/tickets
#
# there is an official Ruby Library for interacting with the Lighthouse API
# however we do not use it in this example in order to show how to do basic REST operations
# with plain Net:HTTP and Rhosync
#
# EXAMPLE XML for a ticket
# <ticket>
#   <assigned-user-id type="integer">9435</assigned-user-id>
#   <attachments-count type="integer">0</attachments-count>
#   <closed type="boolean">false</closed>
#   <created-at type="datetime">2008-12-19T11:00:16-08:00</created-at>
#   <creator-id type="integer">9435</creator-id>
#   <milestone-id type="integer">26804</milestone-id>
#   <number type="integer">1</number>
#   <permalink>show-tickets</permalink>
#   <priority type="integer">1</priority>
#   <project-id type="integer">22198</project-id>
#   <state>new</state>
#   <tag nil="true"></tag>
#   <title>Show tickets</title>
#   <updated-at type="datetime">2008-12-19T11:00:56-08:00</updated-at>
#   <user-id type="integer">9435</user-id>
# </ticket>

class LighthouseTickets < SourceAdapter
  
  include RestAPIHelpers
  
  # login and logoff are left intentionally unimplemented (i.e. we use baseclass implementation) in REST

  # curl -u "<API key>:x" -H 'Accept: application/xml'  http://<account>.lighthouseapp.com/projects/<project-id>/tickets.xml
  def query
    log "LighthouseTickets query"
    
    @result = []
    
    # iterate over all projects and get the tickets for for each
    # we use the IDs of the projects already synced in LighthouseProjects adapter
    projectSource = Source.find_by_adapter("LighthouseProjects")
    projects = ObjectValue.find(:all, :conditions => {
      :source_id => projectSource.id, :update_type => 'query',
      :attrib => 'name', :user_id=>@source.current_user.id})
      
    projects.each do |project|
      puts "project = #{project.value}"  
      uri = URI.parse(base_url)
      
      # up to 20 pages at 30 tickets per page = 600 tickets
      1.upto(20) do |page|
        req = Net::HTTP::Get.new("/projects/#{project.object}/tickets.xml?q=state:open&page=#{page}", 'Accept' => 'application/xml')
        req.basic_auth @source.credential.token, "x"
        response = Net::HTTP.start(uri.host,uri.port) do |http|
          http.set_debug_output $stderr
          http.request(req)
        end
        xml_data = XmlSimple.xml_in(response.body); 

        # if there are no tickets this will be nil
        if xml_data["ticket"]
          @result = @result + xml_data["ticket"]
        else
          break
        end
      end
      
      
    end
  end

  def sync
    if @result
      log "LighthouseTickets sync, with #{@result.length} results"
    else
      log "LighthouseTickets sync, ERROR @result nil"
      return
    end
    
    @result.each do |ticket|
      # construct unique ID for ticket, tickets are identified by project-id/number in lighthouse
      # and number itself is not unique
      id = "#{ticket['project-id'][0]['content']}-#{ticket['number'][0]['content']}"
      
      # iterate over all possible values, if the value is not found we just pass "" in to rhosync
      %w(assigned-user-id body closed created-at creator-id milestone-id number priority state tag title updated-at project-id user-id).each do |key|
        value = ticket[key] ? ticket[key][0] : ""
        add_triple(@source.id, id, key.gsub('-','_'), value, @source.current_user.id)
        # convert "-" to "_" because "-" is not valid in ruby variable names   
      end    
    end
  end

# Example of how you would test this API on the command line
#   curl -u "<API key>:x" -d "<ticket><title>new ticket</title></ticket>" -H 'Accept: application/xml' 
#   -H 'Content-Type: application/xml' http://<account>.lighthouseapp.com/projects/<project-id>/tickets.xml

  def create(name_value_list)
    log "LighthouseTickets create"
    
    get_params(name_value_list)
    xml_str = xml_template(params)
    
    uri = URI.parse(base_url)
    Net::HTTP.start(uri.host) do |http|
      http.set_debug_output $stderr
      request = Net::HTTP::Post.new(uri.path + "/projects/#{params['project_id']}/tickets.xml", {'Content-type' => 'application/xml'})
      request.body = xml_str
      request.basic_auth @source.credential.token, "x"
      response = http.request(request)
      # log response.body
      
      # case response
      # when Net::HTTPSuccess, Net::HTTPRedirection
      #   # OK
      # else
      #   raise "Failed to create  ticket"
      # end
    end
  end

  def update(name_value_list)
    log "++LighthouseTickets update"
    
    get_params(name_value_list)
    complete_missing_params
    project, number = split_id(params['id'])

    xml_str = xml_template(params)

    uri = URI.parse(base_url)
    Net::HTTP.start(uri.host) do |http|
      http.set_debug_output $stderr
      request = Net::HTTP::Put.new(uri.path + "/projects/#{project}/tickets/#{number}.xml", {'Content-type' => 'application/xml'})
      request.body = xml_str
      request.basic_auth @source.credential.token, "x"
      response = http.request(request)

      # case response
      # when Net::HTTPSuccess, Net::HTTPRedirection
      #   # OK
      # else
      #   raise "Failed to create  ticket"
      # end
    end
  end

  # {"id"=>"500/8"}, delete ticket #8 from project #500
  def delete(name_value_list)
    log "--LighthouseTickets delete"
    
    get_params(name_value_list)
    project, number = split_id(params['id'])
    
    uri = URI.parse(base_url)
    Net::HTTP.start(uri.host) do |http|
     http.set_debug_output $stderr
     url = uri.path + "/projects/#{project}/tickets/#{number}.xml"
     request = Net::HTTP::Delete.new(url, {'Content-type' => 'application/xml'})
     request.basic_auth @source.credential.token, "x"
     response = http.request(request)

     # case response
     # when Net::HTTPSuccess, Net::HTTPRedirection
     #   # OK
     # else
     #   raise "Failed to create  ticket"
     # end
    end
  end
  
  protected
  
 # use this to fill params from the DB to make a complete request
  def complete_missing_params
    %w(assigned-user-id body closed creator-id milestone-id number priority state tag title project-id).each do |key|
      searchkey = key.gsub('-','_')
      unless params[searchkey]
        o=ObjectValue.find(:first, :conditions => ["source_id = ? and object = ? and attrib = ?", 
          @source.id, params['id'], searchkey])
        params.merge!(key => o.value) if o
      end  
    end
  end
  
  # construct and fill in XML template for lighthouse xml API
  def xml_template(params)
    xml_str  = <<-EOT
    <ticket>
      <assigned-user-id type="integer">#{params['assigned_user_id']}</assigned-user-id>
      <body>#{params['body']}</body>
      <milestone-id type="integer">#{params['milestone_id']}</milestone-id>
      <state>#{params['state']}</state>
      <closed type="boolean">#{params['closed']}</closed>
      <title>#{params['title']}</title>
      <priority type="integer">#{params['priority']}</priority>
      <tag>#{params['tag']}</tag>
    </ticket>
    EOT
    
    log xml_str
    xml_str
  end
  

end