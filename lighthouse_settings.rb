#
# Author: Vidal Graupera
#
# 

class LighthouseSettings < SourceAdapter
  
  include RestAPIHelpers
  
  def query
    log "LighthouseSettings query"
    
    @result = [ {"lighthouse_id" => @source.credential.login.to_s } ]
  end
  
  def sync  
    @result[0].each do |key, value|
      add_triple(@source.id, "doesnotmatter", key, value.to_s, @source.current_user.id)
    end
  end
  
end