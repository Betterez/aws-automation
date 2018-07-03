require_relative  'AwsInstance'

class InstancesManager
  def initialize
    @instances = {}
    @mutex = Mutex.new
  end

  def add_instance(instance, status = 'initial')
    @mutex.synchronize do
      @instances[instance.get_aws_id] = {status: status,instance: instance}
    end
  end

  def update_instance_status(instance, status)
    @mutex.synchronize do
      if @instances.has_key?(instance.get_aws_id)
        @instances[instance.get_aws_id][:status] = status
      end
    end
  end

  def get_instances_with_status(status)
    result = []
    @instances.keys.each do |key|
      result << @instances[key][:instance] if @instances[key][:status] == status
    end
    result
   end
  def delete_instance(instance)
    @mutex.synchronize{
      @instances.delete(instance.get_aws_id)
    }
  end
  def delete_instances_with_status(status)
    @mutex.synchronize{
      @instances.delete_if { |key , value | value[:status]==status}
    }
  end
  def delete_and_terminate_instances_with_status(status)
    @mutex.synchronize{
      @instances.keys.each do |key|
        if @instances[key][:status]==status
          @instances[key][:instance].terminate_instance
          @instances.delete(key)
        end
      end
    }
  end

end
