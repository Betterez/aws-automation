require_relative 'Helpers'
require_relative 'Notifire'
require_relative 'VaultDriver'

class Syslogger
  def initialize(vault_driver)
    @vault_driver = vault_driver
  end

  def check_record_exists(aws_instance)
    result = aws_instance.run_ssh_command('cat /etc/rsyslog.conf |grep logentries')
    return false if result.strip == ''
    true
  end

  ##  add_record_to_rsyslog - adding a record to syslog
  # return boolean result add (yes/no) and an error code
  def add_record_to_rsyslog(aws_instance)
    service_name=aws_instance.get_tag_by_name("Repository")
    return false,"No repository value" if service_name.nil?||service_name.strip==""

    data, code = @vault_driver.get_json("secret/#{service_name}")
    return false, code if code > 399
    return false, 'record already exists!' if check_record_exists
    return false, 'no logentries token found' unless data.key?('logentries_syslog_token')
    footer = "'$template Logentries,\"#{data['logentries_syslog_token']} %HOSTNAME% %syslogtag%%msg%\"\n *.* @@data.logentries.com:80;Logentries'"
    result = aws_instance.run_ssh_command("echo #{footer} | sudo tee --append /etc/rsyslog.conf")
    if check_record_exists
      aws_instance.run_ssh_command('sudo service rsyslog restart')
    else
      return false, 'failed to setup command'
    end
    aws_instance.run_ssh_command('logger -t test Testing logger command')
    [true, nil]
  end

  ## gets a list of active repository based on the running servers in this environment
  # environment +string+ - the environment to check
  # return an array of strings, representing the repositories
  def self.get_all_active_repositories_for_environment(environment)
    aws_instances = AwsInstance.get_instances_with_filters([
                                                             { name: 'tag:Environment', values: [environment] },
                                                             { name: 'instance-state-name', values: ['running'] }
                                                           ], aws_settings)
    return [] if aws_instances.empty?
    instance_services = {}
    aws_instances.each do |instance|
      if !instance.get_tag_by_name('Repository').nil? && instance.get_tag_by_name('Repository').strip != ''
        instance_services[instance.get_tag_by_name('Repository')] = 1
      end
      logger = Syslogger.new(instance, driver, instance.get_tag_by_name('Repository'))
      puts logger.add_record_to_rsyslog
    end
    instance_services.keys
  end

  ## get_all_repositories_servers_per_environment - returns all repo servers that has a repository value
  # environment +string+ - the environment to check
  # return an array of AwsInsrtances
  def self.get_all_repositories_servers_per_environment(environment)
    instance_services=[]
    aws_instances = AwsInstance.get_instances_with_filters([
                                                             { name: 'tag:Environment', values: [environment] },
                                                             { name: 'instance-state-name', values: ['running'] },
                                                           ], aws_settings)
    aws_instances.each do |instance|
      if !instance.get_tag_by_name('Repository').nil? && instance.get_tag_by_name('Repository').strip != ''
        instance_services.push(instance)
      end
    end
  end

  ## generate_service_json generage a service json file
  # instance_services - array of string representing the repositories of running instances
  # vault_driver - vault driver object that is already initialized
  # return json string
  def self.generate_service_json(instance_services,vault_driver)
    service_json_to_create=[]
    dump_data=""
    instance_services.each do |instance_service|
      next if instance_service.nil? or instance_service.strip==""
      data, code=vault_driver.get_json("secret/#{instance_service}")
      if code>399 or data.nil?
        service_hash={instance_service=>{"service_name"=>instance_service,"environments"=>[environment],"path"=>"/","use_log_entries"=>true}}
        service_json_to_create.push(service_hash)
        puts "Service #{instance_service} got #{code} with #{data}, moving on..."
        next
      end
      if data.has_key?("logentries_token")
        puts "adding syslog to: service #{instance_service}"
        driver.put_json_for_repo(instance_service,{"logentries_syslog_token":data['logentries_token']},true)

      else
        service_hash={instance_service=>{"service_name"=>instance_service,"environments"=>[environment],"path"=>"/","use_log_entries"=>true}}
        service_json_to_create.push(service_hash)
        puts "service #{instance_service} does not have a token!"
      end
    end
    if instance_services.length>0
      service_json_to_create.each_with_index do |service_hash,index|
        if index==(service_json_to_create.length-1)
          dump_data+=service_hash.to_json[1,service_hash.to_json.length]
        else
          dump_data+="#{service_hash.to_json[0,service_hash.to_json.length-1]},\r\n"
        end
      end
    end
  end

end
