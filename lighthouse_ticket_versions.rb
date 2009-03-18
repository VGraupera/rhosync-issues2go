#
# Author: Vidal Graupera
#
# Example REST source adapter using http://lighthouseapp.com/api/tickets
#
# Gets changes and comments for a ticket
#
# Calls - GET /projects/#{project_id}/tickets/#{number}.xml
# This fetches not only the latest version of the ticket, but all of the previous versions.
# We already got the current attributes of the ticket in LighthouseTickets. This code is to get
# the versions which includes the changes and comments

class LighthouseTicketVersions < SourceAdapter
  
  include RestAPIHelpers
  include ActiveSupport::Inflector

  def query
    log "LighthouseTicketVersions query"
    @result = []
    
    # iterate over all tickets and get the versions for each
    lighthouseTickets = Source.find_by_adapter("LighthouseTickets")
    tickets = ObjectValue.find(:all, :conditions => ["source_id = ? and update_type = 'query' and attrib = 'title'", 
      lighthouseTickets.id])
          
    tickets.each do |ticket|  
      uri = URI.parse(base_url)
      project, number = split_id(ticket.object)    
      req = Net::HTTP::Get.new("/projects/#{project}/tickets/#{number}.xml", 'Accept' => 'application/xml')
      req.basic_auth @source.credential.token, "x"
      response = Net::HTTP.start(uri.host,uri.port) do |http|
        http.request(req)
      end
      xml_data = XmlSimple.xml_in(response.body); 
      
      # versions is an array of version hashes
      if xml_data["versions"] && xml_data["versions"][0] && xml_data["versions"][0]["version"]
        @result = @result + xml_data["versions"][0]["version"]
      end
    end
  end

  def sync
    if @result
      log "LighthouseTicketVersions sync, with #{@result.length} results"
    else
      log "LighthouseTicketVersions sync, ERROR @result nil"
      return
    end
    
    @result.each do |version|
      # construct unique ID for ticket versions, tickets are identified by project-id/number in lighthouse
      # and number itself is not unique, here we also append the timestamp since there willl always be more 
      # than 1 version for same project_id-number
      id = "#{version['project-id'][0]['content']}-#{version['number'][0]['content']}-#{version['updated-at'][0]['content']}"
      # puts "LighthouseTicketVersions id=#{id}"
      
      # here we just want to know who made the change and when, other fields we dont save to DB
      %w(updated-at user-id).each do |key|
        value = version[key] ? version[key][0] : ""
        add_triple(@source.id, id, key.gsub('-','_'), value, @source.current_user.id)
        # convert "-" to "_" because "-" is not valid in ruby variable names   
      end    
      
      # process the "diffable-attributes"
      change_msg = calculate_change_history(version, YAML::load(version['diffable-attributes'][0]['content']))
            
      add_triple(@source.id, id, "changes", change_msg, @source.current_user.id)
      add_triple(@source.id, id, "ticket_id", "#{version['project-id'][0]['content']}-#{version['number'][0]['content']}", @source.current_user.id)    
    end
  end
  
  def calculate_change_history(version, changes)
    change_msg = ""
    
    if changes && changes.length > 0
      events = ["<<<EOC>>>"] # dummy to indicate end of changes, parsed out by client
      changes.each_pair do |field,value|
        
        # we need to pluck the right value from the diff, the key does not alway match exactly as id is stripped
        # and it is a symbol not a string
        key = case field
        when :milestone:
          "milestone-id"
        when :assigned_user:
          "assigned-user-id"
        else
          field.to_s
        end
        
        value_pre = value
        value_post = eval_value(version[key][0])
        
        if value_post.blank? 
          events << "#{humanize(field)} cleared."
        else
          
          # if we are dealing with a milestone or assigned-user-id, then we need to look up the name
          if (key == "milestone-id")
            
            lighthouseMilestones = Source.find_by_adapter("LighthouseMilestones")
            
            unless value_pre.blank?
              if milestone = ObjectValue.find(:first, :conditions => 
                ["source_id = ? and update_type = 'query' and attrib = 'title' and object = ?", 
                  lighthouseMilestones.id, value_pre])
              
                  value_pre = milestone.value
              end
            end
          
            unless value_post.blank?
              if milestone = ObjectValue.find(:first, :conditions => 
                ["source_id = ? and update_type = 'query' and attrib = 'title' and object = ?", 
                lighthouseMilestones.id, value_post])
              
                value_post = milestone.value
              end
            end
          
          elsif (key == "assigned-user-id")
            
            lighthouseUsers = Source.find_by_adapter("LighthouseUsers")
            
            unless value_pre.blank?
              if assigned = ObjectValue.find(:first, :conditions => 
                ["source_id = ? and update_type = 'query' and attrib = 'name' and object = ?", 
                  lighthouseUsers.id, value_pre])
              
                  value_pre = assigned.value
              end
            end
          
            unless value_post.blank?
              if assigned = ObjectValue.find(:first, :conditions => 
                ["source_id = ? and update_type = 'query' and attrib = 'name' and object = ?", 
                lighthouseUsers.id, value_post])
              
                value_post = assigned.value
              end
            end
            
          end
    
          events << "#{humanize(field)} changed from \"#{value_pre}\" to \"#{value_post}\""
        end
      end
      change_msg = events.join("||||") # assume no ticket contains this in the body
    else
      # if there are no changes then that means there was a comment which is in body
      change_msg = version['body'][0] 
    end
    
    change_msg
  end
      
end