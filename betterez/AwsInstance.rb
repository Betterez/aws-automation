require_relative 'Helpers'
require_relative 'Notifire'
require_relative 'VaultDriver'
require_relative 'Transaction'
require_relative 'ServiceInstaller'
require_relative 'OssecManager'
require_relative 'Syslogger'
require_relative 'InstancesManager'
require 'rubygems'
require 'pty'
require 'net/ssh'
require 'net/scp'
require 'fileutils'

class AwsInstance
  @@time_to_wait = 15
  MAX_THREAD_WAITING = 80
  # setting hash
  attr_accessor(:aws_setup_information)
  attr_accessor(:notifire)
  # amazon instance
  attr_reader(:aws_instance_data)
  # betterez repo
  attr_reader(:repository)
  attr_reader(:instance_type)
  attr_reader(:build_number)
  attr_accessor(:environment)
  attr_reader(:path_name)
  attr_reader(:ami_id)
  attr_reader(:service_type)
  attr_reader(:balancer_configuration)
  attr_accessor(:host_port)
  attr_reader(:name)
  attr_reader(:immune)
  # creates new object.
  # * +instance+ instance from amazon.
  # * +aws_setup_information+ hashed aws_setup_information.
  def initialize(instance, aws_setup_information)
    STDOUT.sync = true
    throw "can't create an instance without setup data" if aws_setup_information.nil?
    @aws_setup_information = aws_setup_information
    @aws_instance_data = instance
    # load tags here
    instance.tags.each do |tag|
      if tag.key == 'Repository'
        @repository = tag.value
      elsif tag.key == 'Build-Number'
        @immune = true if tag.value == '000'
        @build_number = tag.value.to_i
      elsif tag.key == 'Environment'
        @environment = tag.value
      elsif tag.key == 'Path-Name'
        @path_name = tag.value
      elsif tag.key == 'Ami-id'
        @ami_id = tag.value
      elsif tag.key == 'Service-Type'
        @service_type = tag.value
      elsif tag.key == 'Nginx-Configuration'
        @balancer_configuration = tag.value
      elsif tag.key == 'Balancer-Configuration'
        @balancer_configuration = tag.value
      elsif tag.key == 'Port'
        @host_port = tag.value.to_i
      elsif tag.key == 'Name'
        @name = tag.value
      elsif tag.key == 'Immune'
        @immune = true
      end
    end
    @host_port = 3000 if @host_port.nil?
    @ssh_timeout_period = 240_000
    @build_number ||= 0
    @immune = false if @immune.nil?
    @instance_type = instance.instance_type
  end

  def get_aws_id
    @aws_instance_data.instance_id
  end

  ## returns the tag value by it's name
  def get_tag_by_name(name)
    @aws_instance_data.tags.each do |tag_data|
      return tag_data.value if tag_data.key == name
    end
    nil
  end

  def self.time_to_wait
    @@time_to_wait
  end

  def is_elb_instance?
    @balancer_configuration != 'none' && @balancer_configuration != 'worker'
  end

  def is_nginx_instance?
    false
  end

  def get_state_description
    client = Helpers.create_aws_ec2_client
    resp = client.describe_instances(dry_run: false,
                                     instance_ids: [@aws_instance_data.instance_id])
    resp.reservations[0].instances[0].state.name
  end

  # is this instance carrying repository that can be checked.
  # returns +true+ if so.
  def can_health_check?
    return false if @service_type == 'worker'

    true
  end

  def notify(message)
    @notifire.notify(1, message) if !@notifire.nil? && @notifire
  end

  # waits for an instance to reach a state.
  # *  +state+ - +string+. the state code
  def wait_for_state(state)
    current_state = 'unknown'
    while current_state != state
      sleep(10)
      begin
        current_state = get_state_description
      rescue StandardError
        current_state = 'unknown'
      end
    end
  end

  def generate_filters_hash
    filters = {
      'Path-Name' => @path_name,
      'Environment' => @environment,
      'Release' => 'yes',
      'Elb-Type' => @balancer_configuration
    }
    filters
  end

  # +bollean+ checks if this instance ami is up to date
  def is_ami_version_up_to_date(ami_type)
    return false if @ami_id.nil?

    current_ami = AwsInstance.get_ami_id(ami_type)
    return true if @ami_id == current_ami

    false
  end

  # +string+ returns the ip
  def get_access_ip
    if @aws_instance_data.public_ip_address
      return @aws_instance_data.public_ip_address
    end

    @aws_instance_data.private_ip_address
  end

  def get_instance_private_ip_address
    @aws_instance_data.private_ip_address
  end

  # checks if the instance service is healthy.
  # return +boolean+ true if so , or false if not, and +string+ for the output.
  def is_service_healthy?(service_setup_data)
    output = ''
    return true if service_setup_data['deployment']['healthcheck']['perform'] != true

    begin
      notify "healthcheck with #{service_setup_data['deployment']['healthcheck']['command']}"
      output = run_ssh_command("cd /home/bz-app/#{@repository} && #{service_setup_data['deployment']['healthcheck']['command']}")
      return true, output if output.include? service_setup_data['deployment']['healthcheck']['result']
    rescue StandardError => details
      notify(details)
      return false, output
    end
    [false, output]
  end

  # restarts a service
  def restart_service
    ssh_command = "sudo service #{@repository} restart"
    notify run_ssh_command ssh_command
  end

  # stops the machine service
  def stop_service
    ssh_command = "sudo service #{@repository} stop"
    notify run_ssh_command ssh_command
  end

  # updates the instance repository code and restarts the service
  # * +branch_name+ string. the branch to pull from.
  def update_instance_code(service_setup_data)
    service_setup_data[:install_type] = :existing_servers
    stop_service
    load_instance_code service_setup_data
    restart_service
  end

  # update the instance OS, might not work for kernel updates.
  def update_instace_os
    ssh_command = 'sudo apt-get update &&sudo apt-get dist-upgrade -qq && sudo apt-get autoremove -y'
    result = ''
    Net::SSH.start(get_access_ip, 'ubuntu', keys: @aws_setup_information[@environment.to_sym][:keyPath], timeout: @ssh_timeout_period) do |ssh|
      ssh.exec(ssh_command) do |_channel, _stream, data|
        result += data
      end
    end
    result
  end

  # returns the current node version of this server
  def get_node_version
    run_ssh_command('node --version')
  end

  # set up a new build number. create if does not exist
  # * +build_number+ Integer. the build number to set.
  def update_build_number(build_number)
    result = ''
    client = Helpers.create_aws_ec2_client
    client.create_tags(dry_run: false,
                       resources: [@aws_instance_data.instance_id],
                       tags: [{ key: 'Build-Number', value: build_number }])
    result += run_ssh_command("echo #{build_number} | sudo tee /home/bz-app/build_number.txt")
    result += run_ssh_command("sudo service #{@repository} restart")
    result
  end

  # run ssh command tried for +loops+ loops
  def run_ssh_command(ssh_command, loops = 5, command_delay = 5)
    result = ''
    done = true
    (0...loops).each do
      begin
        Net::SSH.start(get_access_ip, 'ubuntu', keys: @aws_setup_information[@environment.to_sym][:keyPath]) do |ssh|
          result = ssh.exec!(ssh_command).to_s
        end
      rescue StandardError
        done = false
        sleep command_delay
      end
      break if done
    end
    result
  end

  ## runs ssh command and streams the output to stdout
  def run_ssh_in_terminal(command)
    Net::SSH.start(get_access_ip, 'ubuntu', keys: @aws_setup_information[@environment.to_sym][:keyPath]) do |ssh|
      signal = ssh.open_channel do |channel|
        channel.send_channel_request 'shell' do |_ch, success|
          if success
            puts 'user shell started successfully'
          else
            puts 'could not start user shell'
          end
        end
        channel.on_data do |_term, data|
          STDOUT.sync = true
          puts data
        end
        channel.request_pty do |channel, _data|
          channel.send_data("#{command}\n")
          channel.send_data("exit\n")
        end
      end
      signal.wait
    end
  end

  ## update_logger_config
  # update logger config data for log entries if exists in vault
  def update_logger_config(service_setup_data)
    driver = VaultDriver.from_secrets_file service_setup_data[:environment]
    service_name = service_setup_data['deployment']['service_name']
    logger = Syslogger.new(driver)
    if logger.check_record_exists(self)
      puts 'record already exists'
      return
    end
    result, error = logger.add_record_to_rsyslog(self)
    if result
      puts 'syslog updated!'
    else
      puts "error #{error}" unless error.nil?
      puts 'not updated'
    end
  end

  def self.run_pci_dss_check(service_setup_data, aws_setup_information)
    if service_setup_data[:pci_dss]
      Helpers.log 'checking psi dss settings'
      Helpers.log "loading vault infor for #{service_setup_data[:environment]}"
      driver = VaultDriver.from_secrets_file service_setup_data[:environment]
      if aws_setup_information.key?(:secrets)
        puts 'vault required.'
        puts 'vault unlocked' if driver.unlock_vault(aws_setup_information[:secrets][:vault][:keys]) == 200
      else
        puts 'no vault secrets file.'
      end
      Helpers.log 'loadning dss information'
      checker = SecurityChecker.new
      Helpers.log 'loading aws keys'
      checker.get_all_aws_keys
      Helpers.log 'loading aws keys done'
      Helpers.log "checking security settings for service #{service_setup_data['deployment']['service_name']}"
      ok, error = checker.check_security_for_service(service_setup_data['deployment']['service_name'], driver)
      throw "service #{service_setup_data['deployment']['service_name']} can't be updated - #{error}" unless error.nil?
    end
  end

  def upload_data_to_file(data, remote_file_name)
    Net::SSH.start(get_access_ip, 'ubuntu', keys: @aws_setup_information[@environment.to_sym][:keyPath], timeout: @ssh_timeout_period) do |ssh|
      ssh.scp.upload!(StringIO.new(data), remote_file_name)
    end
  end

  def upload_file_to_host(local_file_name, remote_file_name)
    Net::SSH.start(get_access_ip, 'ubuntu', keys: @aws_setup_information[@environment.to_sym][:keyPath], timeout: @ssh_timeout_period) do |ssh|
      ssh.scp.upload!(local_file_name, remote_file_name)
    end
  end

  # Terminate current instance
  def terminate_instance
    client = Helpers.create_aws_ec2_client
    client.terminate_instances(dry_run: false,
                               instance_ids: [@aws_instance_data.instance_id])
  end

  # checks if this is a betterez-app server.
  def is_app_instance?
    if @service_type == 'http' && @path_name == '/' && @balancer_configuration == 'app'
      return true
    end

    false
  end

  # gets an instance from it's name, or nil if we can't get it.
  # * +instance_name+ string the instance name.
  def self.get_from_name(instance_name, aws_setup_information)
    client = Helpers.create_aws_ec2_client
    resp = client.describe_instances(dry_run: false,
                                     filters: [
                                       {
                                         name: 'tag:Name',
                                         values: [instance_name]
                                       }
                                     ])
    resp.reservations.each do |reservation|
      reservation.instances.each do |instance|
        return AwsInstance.new(instance, aws_setup_information)
      end
    end
    nil
  end

  ## create aws instances.
  # * +service_setup_data+ - service specific data
  # * +aws_setup_information+ - environment and keys data
  def self.create_aws_instances(service_setup_data, aws_setup_information, notifire)
    throw 'no aws setup info' if aws_setup_information.nil?
    instance_threads = []
    instances_data = []
    instances_manager = InstancesManager.new

    notifire.notify(1, 'getting ami id')
    total_servers_number = if service_setup_data[:debug] || service_setup_data[:ami]
                             1
                           else
                             3
                           end
    puts "server :#{service_setup_data['machine']['servers_count']}"
    ami_id = AwsInstance.get_ami_id(service_setup_data['machine']['image'])
    unless ami_id
      notifire.notify(1, "sorry! there is no ami id for type #{service_setup_data['machine']['image']}! Are you missing a packer run?")
      return []
    end
    total_servers_number = service_setup_data[:servers_count] * 2 if service_setup_data[:servers_count] > 1
    current_environment_data = aws_setup_information[service_setup_data[:environment].to_sym]
    throw "no infrastructure data for #{service_setup_data[:environment]}"  if current_environment_data.nil?
    puts "total_servers_number=#{total_servers_number}"
    if service_setup_data[:servers_count]
      current_server_index = 0
      current_infra_index = 0
      while current_server_index < total_servers_number
        if current_infra_index + 1 > current_environment_data[:infraStructure].length
          current_infra_index = 0
        end
        instances_data << { infra_data: current_environment_data[:infraStructure][current_infra_index], ami_id: ami_id }
        current_infra_index += 1
        current_server_index += 1
      end
    else
      current_environment_data[:infraStructure].each do |infra_data|
        instances_data << { infra_data: infra_data, ami_id: ami_id }
      end
    end
    run_pci_dss_check(service_setup_data, aws_setup_information)
    transaction = Transaction.new service_setup_data[:servers_count]
    limiter = Random.new
    instances_data.each do |instance_data|
      sleep ( 0.1 + limiter.rand(2000) / 100)
      instance_threads << Thread.new do
        aws_instance = create_service_instance(service_setup_data, aws_setup_information, notifire, instance_data, transaction, instances_manager)
      end
    end
    keep_waiting = true
    all_thread_wait = 0

    while all_thread_wait < AwsInstance::MAX_THREAD_WAITING && keep_waiting == true
      if service_setup_data[:servers_count] <= instances_manager.get_instances_with_status(InstancesManager::READY_STATUS).length
        keep_waiting = false
      end
      all_thread_wait += 1
      sleep 15
      puts ''
      puts "..:: polling number #{all_thread_wait},keep_waiting=#{keep_waiting}, ready servers:#{instances_manager.get_instances_with_status(InstancesManager::READY_STATUS).length} ::.."
      puts ''
    end
    puts ''
    puts "..:: done waiting: all_thread_wait:#{all_thread_wait}, keep_waiting=#{keep_waiting} ::.."
    puts ''
    instance_threads.each(&:kill)

    if instances_manager.get_instances_with_status(InstancesManager::READY_STATUS).length < service_setup_data[:servers_count]
      if service_setup_data[:debug]
        notifire.notify 1, 'keeping failed servers, debug'
      else
        notifire.notify 1, 'created servers are below require number, terminating.'
        instances_manager.delete_and_terminate_all_instances
      end
    end

    if instances_manager.get_instances_with_status(InstancesManager::READY_STATUS).length > service_setup_data[:servers_count]
      notifire.notify 1, 'terminating spare servers'
      instances_manager.limit_number_of_instances_with_status(InstancesManager::READY_STATUS, service_setup_data[:servers_count])
    end
    instances_manager.delete_and_terminate_instances_with_status('initial')
    # remove cloudwatch cache.
    # set ossec
    instances_manager.get_instances_with_status(InstancesManager::READY_STATUS).each do |instance|
      instance.run_ssh_command 'rm -rf /var/tmp/aws-mon/instance-id'
      instance.update_ossec_settings unless service_setup_data[:ami]
    end
    notifire.notify 1, 'done'
    notifire.notify 1, "#{instances_manager.get_instances_with_status(InstancesManager::READY_STATUS).length} servers created."
    if service_setup_data[:ami]
      notifire.notify 1, 'creating ami.'
      instances_manager.get_instances_with_status(InstancesManager::READY_STATUS)[0].create_ami(service_setup_data)
      notifire.notify 1, 'terminating instance.'
      instances_manager.get_instances_with_status(InstancesManager::READY_STATUS)[0].terminate_instance
      return []
    end
    instances_manager.get_instances_with_status(InstancesManager::READY_STATUS)
  end

  ## checks if this instance has ossec agent on it
  # returns +true+ if so, or +false+ if not
  def is_instance_ossec_agent?
    listing = run_ssh_command 'sudo ls /var/ossec/etc'
    if listing.index('cannot access').nil?
      return true
    else
      notify 'seems to be not an ossec instance:'
      notify listing
      return false
    end
  end

  def update_init_file_and_restart(service_setup_data)
    throw 'nil aws_setup_information' if @aws_setup_information.nil?
    # puts "\n\n\nservice_setup_data=#{service_setup_data}\n\n\n"
    # puts "\n\n\naws_setup_information=#{@aws_setup_information}\n\n\n"
    service_installer = ServiceInstaller.new(service_setup_data, @aws_setup_information[service_setup_data[:environment].to_sym])
    service_installer.install_service(self)
    # remote_file_name = "/home/ubuntu/#{@repository}.conf"
    # init_file_data = AwsInstance.generate_init_file(service_setup_data, @aws_setup_information, @environment.to_sym)
    # upload_data_to_file(init_file_data[0][:script], remote_file_name)
    # ssh_command = "sudo mv #{remote_file_name} /etc/init/#{@repository}.conf && sudo service #{@repository} restart"
    # run_ssh_command ssh_command
  end

  def load_instance_code(service_setup_data)
    service_name = service_setup_data['deployment']['service_name']
    temp_folder = "temp/#{Thread.current.object_id}/"
    FileUtils.mkdir_p temp_folder unless Dir.exist?(temp_folder)
    existing_servers = ((service_setup_data.key? :install_type) && (service_setup_data[:install_type] == :existing_servers))
    if existing_servers
      notify 'updating existing servers'
    else
      notify 'updating new servers' unless existing_servers
    end
    case service_setup_data['deployment']['source']['type']
    when 'nop'
      notify 'no code to load'
    when 'git'
      branch_name = service_setup_data['deployment']['source']['branch_name']
      git_repo = service_setup_data['deployment']['source']['repo']
      notify "git: loading from #{git_repo} on branch #{branch_name} .."
      if existing_servers
        ssh_command = " if [ -d '/home/bz-app/#{service_name}/.git' ]; then echo 'repository ok'; else echo 'not exists'; fi"
        results = run_ssh_command ssh_command
        puts "repository location #{results}"
        throw 'bad location' if results == 'not exists'
        ssh_command = "cd /home/bz-app/#{service_name} " \
                      "&& sudo -H -u bz-app bash -c 'git stash'" \
                      "&& sudo -H -u bz-app bash -c 'git checkout #{branch_name}'" \
                      " && sudo -H -u bz-app bash -c 'git pull origin #{branch_name}'"
      else
        ssh_command = "cd /home/bz-app && sudo -H -u bz-app bash -c 'git clone #{git_repo}'"
        run_ssh_command ssh_command
        unless branch_name == 'master'
          notify "switching to #{branch_name}"
          ssh_command = "cd /home/bz-app/#{git_repo} && sudo -H -u bz-app bash -c 'git checkout #{branch_name}'"
          run_ssh_command ssh_command
        end
      end
      if existing_servers
        notify "updating existing servers code base (#{ssh_command})"
        notify run_ssh_command ssh_command
      end
      notify 'done'
      unless existing_servers
        ssh_command = "cd /home/bz-app/#{service_name} && sudo -H -u bz-app bash -c 'git checkout #{branch_name}'"
        run_ssh_command ssh_command
      end
    when 's3'
      notify 'loading from s3'
      filename = service_setup_data['deployment']['source']['bucket']
      # puts "loading #{filename}"
      filename += '.tar.gz' if filename.index('tar.gz').nil?
      notify 'creating s3 client'
      s3 = Aws::S3::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
      resp = s3.list_objects(bucket: service_setup_data['deployment']['source']['bucket'],
                             delimiter: 'Delimiter',
                             encoding_type: 'url')
      notify 'loading objects'
      selected_object = nil
      resp.contents.each do |s3_object|
        if s3_object.key.index('_20')
          selected_object = s3_object if selected_object.nil?
          selected_object = s3_object if selected_object.key < s3_object.key
        end
      end
      throw 'No s3 object found!' if selected_object.nil?
      notify "#{selected_object.key} was selected, pulling to local temp storage... "
      notify "local file name #{temp_folder + filename}"
      File.open(temp_folder + filename, 'wb') do |file|
        s3.get_object(bucket: service_setup_data['deployment']['source']['bucket'], key: selected_object.key) do |chunk|
          file.write(chunk)
        end
      end
      notify 'uploading s3 to destination'
      upload_file_to_host(temp_folder + filename, '/home/ubuntu/')
      notify 'done, showing file listings:'
      notify run_ssh_command('ls -shla')
      notify 'extracting...'
      notify run_ssh_command("tar -xzf #{filename}")
      notify run_ssh_command("sudo mkdir -p /home/bz-app/#{service_name} && sudo chown -R bz-app:bz-app /home/bz-app/")
      notify run_ssh_command("sudo mv /home/ubuntu/#{service_name} /home/bz-app/#{service_name} && sudo chown bz-app /home/bz-app/#{service_name}")
      run_ssh_command("echo #{service_setup_data[:build_number]} | sudo tee /home/bz-app/build_number.txt")
    end
    sleep 5
    if !service_setup_data['machine']['install'].nil? && !service_setup_data['machine']['install'].empty?
      notify 'installing....'
      service_setup_data['machine']['install'].each do |command|
        next if command == ''

        notify "running #{command}"
        ssh_command = "cd /home/bz-app/#{service_name} && sudo -H -u bz-app bash -c '#{command}'"
        run_queued_ssh_command(ssh_command, true)
        # run_ssh_in_terminal(ssh_command)
        # notify run_ssh_command(ssh_command)
      end
    elsif !service_setup_data['machine']['fast_install'].nil? && !service_setup_data['machine']['fast_install'].empty?
      notify 'fast installing....'
      service_setup_data['machine']['fast_install'].each do |command|
        next if command == ''

        notify "running #{command}"
        ssh_command = "cd /home/bz-app/#{service_name} && sudo -H -u bz-app bash -c '#{command}'"
        run_queued_ssh_command(ssh_command, false)
      end
    else
      notify 'nothing to install...'
    end
    notify 'service code loaded.'
  end

  def run_queued_ssh_command(command, run_in_terminal)
    puts "executing queued command: #{command},#{run_in_terminal}"
    failed_command_executions = 0
    command_done_executing = false
    sleep_counter = 0
    until command_done_executing
      sleep_counter = 0
      command_thread = Thread.new do
        run_ssh_in_terminal(command) if run_in_terminal
        run_ssh_command(command) unless run_in_terminal
        command_done_executing = true
      end
      until command_done_executing
        sleep 5
        sleep_counter += 1
        puts "clock #{sleep_counter} out of 96\r\n"
        if sleep_counter > 60 # 8 minutes max
          Thread.kill(command_thread)
          break
        end
      end
      failed_command_executions += 1
      throw "command #{command} failed to execute" if failed_command_executions > 4
    end
  end

  ## Creates a single service instance
  # * +service_setup_data+ - service secific data
  # * +aws_setup_information+ - environment data and other
  # * +instance_setup_data+ - instance data and other
  # * +notifire+ - notifire interface
  # * +transaction+ - instance thread transactio data
  def self.create_service_instance(service_setup_data, aws_setup_information, notifire, instance_setup_data, transaction, instances_manager)
    client = Helpers.create_aws_ec2_client
    failed_attempts = 0
    current_environment_data = aws_setup_information[service_setup_data[:environment].to_sym]
    server_name = "#{service_setup_data['deployment']['service_name']}_#{Helpers.create_time_date_string}_#{Helpers.create_random_string(6)}"
    notifire.notify 1, "creating server #{server_name} with #{instance_setup_data[:ami_id]}"
    selected_instance_type = service_setup_data['machine']['instance_type']
    selected_instance_type = current_environment_data[:instanceType] if selected_instance_type.nil?

    resp = client.run_instances(dry_run: false,
                                block_device_mappings: [
                                  {
                                    device_name: "/dev/sda1",
                                    ebs: {
                                      volume_size: 100,
                                    },
                                  },
                                ],
                                image_id: instance_setup_data[:ami_id],
                                min_count: 1,
                                max_count: 1,
                                key_name: current_environment_data[:keyName],
                                security_group_ids: [instance_setup_data[:infra_data][:securityGroup]],
                                instance_type: selected_instance_type,
                                placement: {
                                  availability_zone: instance_setup_data[:infra_data][:availabilityZone],
                                  tenancy: 'default'
                                },
                                monitoring: {
                                  enabled: true, # required
                                },
                                subnet_id: instance_setup_data[:infra_data][:subnet],
                                disable_api_termination: false)
    instance_data = resp.instances[0]
    aws_instance = AwsInstance.new(instance_data, aws_setup_information)
    notifire.notify 1, "#{Thread.current.object_id} waiting for it to run"
    aws_instance.wait_for_state('running')
    # registers iam for cloud watch.
    client.associate_iam_instance_profile(
      iam_instance_profile: { # required
        arn: Helpers.get_cloud_ern,
        name: 'CloudWatcher'
      },
      instance_id: aws_instance.get_aws_id, # required
    )
    notifire.notify 1, 'creating tags'
    service_setup_data['deployment']['path_name'] = '' if service_setup_data['deployment']['path_name'].nil?
    client.create_tags(dry_run: false,
                       resources: [instance_data.instance_id],
                       tags: [
                         { key: 'Ami-id', value: instance_setup_data[:ami_id] },
                         { key: 'Build-Number', value: '000' },
                         { key: 'Environment', value: service_setup_data[:environment] },
                         { key: 'Name', value: server_name },
                         { key: 'Nginx-Configuration', value: service_setup_data['deployment']['nginx_conf'] },
                         { key: 'Path-Name', value: service_setup_data['deployment']['path_name'] },
                         { key: 'Repository', value: service_setup_data['deployment']['service_name'] },
                         { key: 'Service-Type', value: service_setup_data['deployment']['service_type'] }
                       ])
    notifire.notify 1, "#{Thread.current.object_id} reloading instance"
    resp = client.describe_instances(dry_run: false,
                                     instance_ids: [instance_data.instance_id])
    instance_data = resp.reservations[0].instances[0]
    if service_setup_data[:ami]
      @balancer_configuration = 'none'
      notifire.notify 1, "This service is an ami template 'none' will be the balancer configuration."
    end
    aws_instance = AwsInstance.new(instance_data, aws_setup_information)
    instances_manager.add_instance(aws_instance)
    aws_instance.notifire = notifire
    failed_attempts = 0
    maximum_attempts = 14
    while failed_attempts < maximum_attempts
      begin
        aws_instance.run_ssh_command('ls')
        notifire.notify 1, "connected to server #{aws_instance.get_access_ip}"
        failed_attempts = 0
        break
      rescue StandardError
        notifire.notify 1, "connection to server #{aws_instance.get_access_ip} failed, retrying, #{failed_attempts + 1} of #{maximum_attempts} maximum attempts "
        sleep(10)
        failed_attempts += 1
      end
    end
    if failed_attempts > 0
      if service_setup_data[:debug]
        notifire.notify 1, 'keeping failed servers, debug'
      else
        notifire.notify(1, 'terminating instance due to failure')
        aws_instance.terminate_instance
      end
      return nil
    end
    begin
      # load service code
      aws_instance.load_instance_code(service_setup_data)
      # upload service file
      service_installer = ServiceInstaller.new service_setup_data, current_environment_data
      service_installer.install_service aws_instance
      if transaction.reached_goal?
        aws_instance.terminate_instance
        return nil
      end
      # File.open("service_install#{Thread.current.object_id}.log", 'w') { |file| file.write(install_data) }
      sleep 8
      notifire.notify(1, 'restarting service')
      aws_instance.restart_service
      if transaction.reached_goal?
        aws_instance.terminate_instance
        return nil
      end
      sleep 12
      if aws_instance.can_health_check?
        if transaction.reached_goal?
          aws_instance.terminate_instance
          return nil
        end
        failed_attempts = 0
        health_check_passes = 0
        while failed_attempts < maximum_attempts
          if transaction.reached_goal?
            aws_instance.terminate_instance
            return nil
          end
          notifire.notify(1, "checking service health, #{failed_attempts + 1} of #{maximum_attempts}")
          results = aws_instance.is_service_healthy?(service_setup_data)
          health_check_passes += 1 if results[0]
          if health_check_passes >= 2
            notifire.notify(1, 'service is healthy!')
            failed_attempts = 0
            break
          else
            if failed_attempts == 2
              aws_instance.restart_service
              sleep 20
            end
            notifire.notify(1, "#{Thread.current.object_id} - service is not healthy, retrying")
            notifire.notify(1, "#{Thread.current.object_id} - #{results[1]}")
            sleep 6
            failed_attempts += 1
          end
        end
        if failed_attempts > 0
          if service_setup_data[:debug]
            notifire.notify(1, 'keeping after failed.')
          else
            aws_instance.terminate_instance
          end
          return nil
        end
      else
        notifire.notify(1, "instance doesn't have health check configurations.")
      end
      notifire.notify(1, 'updating build number')
      aws_instance.update_build_number(service_setup_data[:build_number])
      if service_setup_data[:offline_mode]
        aws_instance.update_tag_value('Online','no')
      else
        aws_instance.update_tag_value('Online','yes')
      end
      if service_setup_data['deployment']['healthcheck'].key?('path')
        aws_instance.update_tag_value('Healtcheck-Path', service_setup_data['deployment']['healthcheck']['path'])
      else
        notifire.notify(1, 'no healthcheck data to set')
      end
      if service_setup_data['deployment']['healthcheck'].key?('port')
        puts 'adding port tag'
        aws_instance.update_tag_value('Healtcheck-Port', service_setup_data['deployment']['healthcheck']['port'].to_s)
        puts 'done adding port tag'
      end
    rescue StandardError => details
      if service_setup_data[:debug]
        puts "error: #{details}"
        notifire.notify 1, 'not terminating after an error, debug mode'
      else
        notifire.notify 1, "error #{details}\r\nTerminating instance."
        aws_instance.terminate_instance
      end
      return nil
    end
    notifire.notify(1, 'instance created!')
    transaction.increase!
    instances_manager.update_instance_status(aws_instance, InstancesManager::READY_STATUS)
    notifire.notify(1, 'leaving aws creator')
    aws_instance
  end

  def update_tag_value(tag_name, tag_value)
    client = Helpers.create_aws_ec2_client
    client.create_tags(dry_run: false,
                       resources: [@aws_instance_data.instance_id], # required
                       tags: [ # required
                         {
                           key: tag_name,
                           value: tag_value
                         }
                       ])
  end

  # In case of an ossec agent installed, setup the correct manger and files.
  def update_ossec_settings
    if is_instance_ossec_agent?
      notify "ossec instance, settings agent for #{@environment}..."
      begin
        ossec_manager = OssecManager.new @environment
      rescue StandardError
        notify "can't initialize ossec server for this environment."
        return nil
      end
      ossec_manager.notifire = @notifire
      begin
        result, install_data = ossec_manager.register_new_agent_with_instance(self)
      rescue StandardError => error
        notify "#{error} when installing ossec"
      end
      if result
        notify "ossec agent installed and running #{install_data}"
      else
        notify "failed to install ossec agent: #{install_data}"
      end
    else
      notify 'this is not an ossec instance. exiting'
      nil
    end
  end

  # Craete aws instances.
  def self.create_aws_instance(service_setup_data, aws_setup_information, _notifire = nil)
    env_settings = aws_setup_information[service_setup_data[:environment]]
    client = Helpers.create_aws_ec2_client
    index = 0
    index = service_setup_data[:infra_index] if service_setup_data[:infra_index]
    _notifire.notify(1, 'getting ami') if _notifire
    ami_id = AwsInstance.get_ami_id(service_setup_data[:ami_type])
    _notifire.notify(1, "ami: #{ami_id}") if _notifire
    throw 'no image id' unless ami_id
    selected_instance_type = service_setup_data['machine']['instance_type']
    selected_instance_type = env_settings[:instanceType] if selected_instance_type.nil?

    resp = client.run_instances(dry_run: false,
                                image_id: ami_id,
                                min_count: 1,
                                max_count: 1,
                                key_name: env_settings[:keyName],
                                security_group_ids: [env_settings[:infraStructure][index][:securityGroup]],
                                instance_type: selected_instance_type,
                                placement: {
                                  availability_zone: env_settings[:infraStructure][index][:availabilityZone],
                                  tenancy: 'default'
                                },
                                monitoring: {
                                  enabled: true, # required
                                },
                                subnet_id: env_settings[:infraStructure][index][:subnet],
                                disable_api_termination: false)
    instance_data = resp.instances[0]
    aws_instance = AwsInstance.new(instance_data, aws_setup_information)
    sleep 10
    aws_instance.wait_for_state('running')
    _notifire.notify(1, 'instance created, creating tags') if _notifire
    client.create_tags(dry_run: false,
                       resources: [instance_data.instance_id],
                       tags: [
                         { key: 'Build-Number', value: service_setup_data[:build_number] },
                         { key: 'Environment', value: service_setup_data[:environment] },
                         { key: 'Name', value: service_setup_data[:server_name] },
                         { key: 'Nginx-Configuration', value: service_setup_data[:nginx_conf] },
                         { key: 'Path-Name', value: service_setup_data[:path_name] },
                         { key: 'Repository', value: service_setup_data[:repo] },
                         { key: 'Service-Type', value: service_setup_data[:service_type] },
                         { key: 'Online', value: 'no' }
                       ])
    _notifire.notify(1, 'done creating tags') if _notifire
    resp = client.describe_instances(dry_run: false,
                                     instance_ids: [instance_data.instance_id])
    instance_data = resp.reservations[0].instances[0]
    aws_instance = AwsInstance.new(instance_data, aws_setup_information)
    sleep 15
    _notifire.notify(1, 'accessing...') if _notifire
    output = aws_instance.run_ssh_command('ls')
    _notifire.notify(1, "output #{output}") if _notifire
    aws_instance
  end

  # gets all the instances that followes the tags in +params+.
  # * +filters+ Array of hashes. tags are listed like this: { name: 'tag:Environment', values: ["some value"] },
  # * +aws_setup_information+ Array of hashes. This is the aws info usually found in settings/aws-data.json
  # +returns+ an array of AwsInstance. empty array if none found.
  def self.get_instances_with_filters(filters, aws_setup_information, zone = nil)
    throw "can't filter instances with nil for aws info" if aws_setup_information.nil?
    all_instances = []
    client = Helpers.create_aws_ec2_client(zone)
    resp = if !filters.nil?
             client.describe_instances(dry_run: false,
                                       filters: filters)
           else
             client.describe_instances(dry_run: false)
           end
    resp.reservations.each do |reservation|
      reservation.instances.each do |instance|
        all_instances.push(AwsInstance.new(instance, aws_setup_information))
      end
    end
    all_instances
  end

  def self.get_instances_with_id(instance_id, aws_setup_information)
    instance_id = [instance_id] if instance_id.is_a? String
    client = Helpers.create_aws_ec2_client
    resp = client.describe_instances(dry_run: false,
                                     instance_ids: instance_id)
    resp.reservations.each do |reservation|
      reservation.instances.each do |instance|
        return AwsInstance.new(instance, aws_setup_information)
      end
    end
  end

  def to_s
    "#{@aws_instance_data.instance_id}(#{@name})-#{@environment}
      \tcode repo:#{@repository}
      \tservice type:#{@service_type}
      \tnginx:#{@balancer_configuration}
      \tbuild number:#{@build_number}"
  end

  # returns last ami image from amazon.
  def self.get_ami_id(image_type)
    client = Helpers.create_aws_ec2_client
    images = []
    resp = client.describe_images(dry_run: false,
                                  filters: [
                                    {
                                      name: 'tag:Type', values: [image_type]
                                    },
                                    {
                                      name: 'state', values: ['available']
                                    }
                                  ])
    return nil if resp.images.length.zero?

    resp.images.each do |image|
      images.push(image)
    end
    images.sort! { |a, b| a.creation_date <=> b.creation_date }
    images[images.length - 1].image_id
  end

  def create_ami(service_setup_data)
    client = Helpers.create_aws_ec2_client
    name = "#{service_setup_data['deployment']['service_name']} #{Helpers.create_time_date_string}"
    resp = client.create_image(
      description: "#{service_setup_data['deployment']['service_name']} ",
      instance_id: get_aws_id,
      name: name
    )
    print "\r\nwaiting for the image to be ready"
    loop do
      resp1 = client.describe_images(
        image_ids: [resp.image_id] # TODO: check the actual format
      )
      break if resp1.images[0][:state] == 'available'

      sleep(10)
      print '.'
    end
    puts "\r\nimage ready, tagging"
    client.create_tags(dry_run: false,
                       resources: [resp.image_id],
                       tags: [
                         { key: 'Build-Number', value: service_setup_data[:build_number] },
                         { key: 'Type', value: "repo" },
                         { key: 'Version', value: service_setup_data[:build_number] },
                         { key: 'Environment', value: service_setup_data[:environment] },
                         { key: 'Repository', value: service_setup_data["deployment"]["service_name"] },
                         { key: 'Service-Type', value: service_setup_data["deployment"]["service_type"] },
                         { key: 'Name', value: name},
                       ])
    puts 'done.'
  end

  alias remove_instance terminate_instance
  alias delete_instance terminate_instance
end
