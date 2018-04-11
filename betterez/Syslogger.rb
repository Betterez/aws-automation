require_relative 'Helpers'
require_relative 'Notifire'
require_relative 'VaultDriver'

class Syslogger
  RSYSLOG_STRING="logentries_syslog_token"
  def initialize(vault_driver)
    @vault_driver = vault_driver
  end

  ## checks if a syslog entry exists for logentries
  # aws_instance -and AwsInstance instances
  # return +boolean+ true or false
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
    return false,"no data for repository #{service_name}" if data.nil? ||data.strip==""
    return false, code if code > 399
    return false, 'record already exists!' if check_record_exists(aws_instance)
    return false, 'no logentries token found' unless data.key?(RSYSLOG_STRING)
    footer = "'$template Logentries,\"#{data[RSYSLOG_STRING]} %HOSTNAME% %syslogtag%%msg%\"\n *.* @@data.logentries.com:80;Logentries'"
    result = aws_instance.run_ssh_command("echo #{footer} | sudo tee --append /etc/rsyslog.conf")
    if check_record_exists(aws_instance)
      aws_instance.run_ssh_command('sudo service rsyslog restart')
    else
      return false, 'failed to setup command'
    end
    aws_instance.run_ssh_command('logger -t test Testing logger command')
    [true, nil]
  end

  ## gets a list of active repository based on the running servers in this environment
  # environment +string+ - the environment to check
  # aws_settings +hash+ - aws settings from settings/aws-data.json
  # return an array of strings, representing the repositories
  def self.get_all_active_repositories_for_environment(environment,aws_settings)
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
    end
    instance_services.keys
  end

  ## adjust_syslog_entry - adding syslog entry from a log entry one
  # vault_driver - +VaultDriver+ instance
  # service_name - +string+
  # return +boolean+ and error
  def self.adjust_syslog_entry(vault_driver,service_name)
    data,err=vault_driver.get_json("secret/#{service_name}")
    return false,err if err
    return false, "key already exists"  if data.has_key?(RSYSLOG_STRING)
    return false, "No log entry " if !data.has_key?("logentries_token")
    code=vault_driver.put_json_for_repo(service_name,{RSYSLOG_STRING=>data["logentries_token"]})
    return true,nil if code<399
    return false,code      
  end

  ## get_all_repositories_servers_per_environment - returns all repo servers that has a repository value
  # environment +string+ - the environment to check
  # aws_settings +hash+ - aws settings from settings/aws-data.json
  # return an array of AwsInsrtances
  def self.get_all_repositories_servers_per_environment(environment,aws_settings)
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
    instance_services
  end

  ## generate_service_json generage a service json file
  # instance_services - array of string representing the repositories of running instances
  # vault_driver - vault driver object that is already initialized
  # return json string
  def self.generate_service_json(instance_services,vault_driver,environment)
    service_json_to_create=[]
    dump_data="{"
    instance_services.each do |instance_service|
      next if instance_service.nil? or instance_service.strip==""
      data, code=vault_driver.get_json("secret/#{instance_service}")
      if code>399 or data.nil?
        service_hash={instance_service=>{"service_name"=>instance_service,"environments"=>[environment],"path"=>"/","use_log_entries"=>true}}
        service_json_to_create.push(service_hash)
        puts "Service #{instance_service} got #{code} with #{data}, moving on..."
        next
      end
      if !data.has_key?("logentries_token")
        puts "adding #{instance_service} to required json..."
        service_hash={instance_service=>{"service_name"=>instance_service,"environments"=>[environment],"path"=>"/","use_log_entries"=>true}}
        service_json_to_create.push(service_hash)
      end
    end
    if instance_services.length>0
      service_json_to_create.each_with_index do |service_hash,index|
        if index!=(service_json_to_create.length-1)
          dump_data+=service_hash.to_json[1,service_hash.to_json.length-2]+",\r\n"
        else
          dump_data+="#{service_hash.to_json[1,service_hash.to_json.length-1]}\r\n"
        end
      end
    end
    return dump_data
  end

  ## check_service_eligibility - checks if this server has an entry in vault
  # service_name - +string+ the service name to chekc in vault.
  # return +boolean+ and error code if present
  def check_service_eligibility(service_name)
    data, code = @vault_driver.get_json("secret/#{service_name}")
    return false, code if code > 399
    if data.has_key?(RSYSLOG_STRING)
      return true, nil
    end
  end


end
