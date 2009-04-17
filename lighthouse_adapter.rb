require 'restclient'

class LighthouseAdapter < SourceAdapter
  include RestAPIHelpers
  
  attr :fieldset
  
  def sync
    if @result
      log "LighthouseAdapter base sync, with #{@result.length} results"
        
      generic_results = []
      @result.each do |item|      
        result = {}
        result["id"] = unique_id(item)
      
        # iterate over all possible values, if the value is not found we just pass "" in to rhosync
        @fieldset.each do |key|
          value = (item[key] && !item[key].empty?) ? item[key][0] : nil
          value = nil unless value.class == String
          result[key.gsub('-','_')] = value
        end
        generic_results << result
      end
      @result = generic_results
      super
    else
      log "LighthouseAdapter base sync, ERROR @result nil"
    end
  end
  
  protected
  
  def unique_id(item)
    item["id"][0]["content"]
  end
end