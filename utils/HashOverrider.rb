class HashOverrider
  attr_accessor :override_name
  attr_accessor :delete_override
  def initialize
    @override_name="override"
    @delete_override=true
  end
    def override_hash!(hash_data, environment)
        return if !hash_data.key?(@override_name) || !hash_data[@override_name].key?(environment)
        master_hash = hash_data[@override_name][environment].clone
        hash_data.delete @override_name if @delete_override        
        remainning_objects = []
        first_time = true
        current_path = []

        while remainning_objects.length > 0 || first_time
            current_overrider = master_hash
            current_data = hash_data
            if !first_time
                current_path = remainning_objects[0]
                remainning_objects.slice! 0
                current_path.each do |key_path|
                    current_overrider = current_overrider[key_path]
                    current_data = current_data[key_path]
                end
            else
                first_time = false
            end

            current_overrider.keys.each do |key|
                if current_overrider[key].class == Hash
                    current_data[key] = {} unless current_data.key? key
                    added_key_path = current_path.clone
                    added_key_path.push key
                    remainning_objects.push added_key_path
                else
                    current_data[key] = current_overrider[key]
                end
            end
        end
    end
end
