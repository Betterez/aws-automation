class InstancesManager
  def initialize
    @instances = {}
    @mutex = Mutex.new
  end

  def add_instance(instance_id, status = 'initial')
    @mutex.synchronize do
      @instances[instance_id] = status
    end
  end

  def update_instance_status(instance_id, status)
    @mutex.synchronize do
      @instances[instance_id] = status
    end
  end

  def get_instances_with_status(status)
    result = []
    @instances.keys.each do |key|
      result << key if @instances[key] == status
    end
    result
   end
end
