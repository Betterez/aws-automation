require_relative 'InstancesManager'

class AmiBuilder
  def self.servers_to_launch(service_setup_data)
    return 1 if service_setup_data[:ami]

    total_servers_number = service_setup_data[:debug] ? 1 : 3
    total_servers_number = service_setup_data[:servers_count] * 2 if service_setup_data[:servers_count].to_i > 1
    total_servers_number
  end

  def self.normalize_ami_server_count!(service_setup_data)
    service_setup_data[:servers_count] = 1 if service_setup_data[:ami]
    service_setup_data
  end

  def self.ensure_base_ami!(ami_type, ami_id)
    if ami_type.nil? || ami_type.to_s.strip.empty?
      raise 'machine.image is missing in service.yml'
    end
    if ami_id.nil? || ami_id.to_s.strip.empty?
      raise "no ami id for type #{ami_type}. Are you missing a packer run?"
    end
  end

  def self.build_ami_and_terminate_builders(instances_manager, service_setup_data, notifire)
    previous_term = trap_cleanup_signal('TERM', instances_manager)
    previous_int = trap_cleanup_signal('INT', instances_manager)
    begin
      ready = instances_manager.get_instances_with_status(InstancesManager::READY_STATUS)
      raise 'no ready instance to create ami' if ready.nil? || ready.empty?

      notify(notifire, 'creating ami.')
      ready[0].create_ami(service_setup_data)
    ensure
      restore_signal('TERM', previous_term)
      restore_signal('INT', previous_int)
      notify(notifire, 'terminating instance(s).')
      instances_manager.delete_and_terminate_all_instances
    end
  end

  def self.notify(notifire, message)
    notifire.notify(1, message) if notifire
  end

  def self.trap_cleanup_signal(signal_name, instances_manager)
    Signal.trap(signal_name) do
      instances_manager.delete_and_terminate_all_instances
      exit 1
    end
  end

  def self.restore_signal(signal_name, previous_handler)
    Signal.trap(signal_name, previous_handler || 'DEFAULT')
  rescue ArgumentError
    Signal.trap(signal_name, 'DEFAULT')
  end

  private_class_method :notify, :trap_cleanup_signal, :restore_signal
end
