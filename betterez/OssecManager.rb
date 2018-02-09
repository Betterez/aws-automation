require 'net/http'
require 'json'
require_relative  'AwsInstance'
require_relative  'Helpers'
require_relative  'Notifire'
require_relative  'VaultDriver'

## ossec manager handling class
class OssecManager
  attr_accessor(:server_port)
  attr_accessor(:server_address)
  attr_accessor(:username)
  attr_accessor(:password)
  attr_accessor(:notifire)
  ## initializing the class
  # * +environment+ - the server environment to operate on
  # server address and login information will be loaded from the vault
  def initialize (environment)
    environment=environment.to_sym if environment.is_a?String
    aws_settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
    throw "can't find this environment,'#{environment}'" if !aws_settings.has_key? environment
    environment_data= aws_settings[environment]
    driver = VaultDriver.from_secrets_file environment.to_s
    if environment_data.key?(:secrets)
        notify 'vault unlocked' if driver.unlock_vault(environment_data[:secrets][:vault][:keys]) == 200
    else
        notify 'no vault secrets file.'
    end
    driver.get_vault_status
    if driver.online && !driver.locked
        vault_data,code = driver.get_json("secret/ossec-manager")
    else
          throw "vault is off line or locked"
    end
    throw "couldn't get ossec data" if code >399
    @username=vault_data['username']
    @password=vault_data['password']
    addresses=OssecManager.get_ossec_manager_ip_for_environment(environment)
    throw "there is no server address for the environment #{environment}" if addresses==nil
    @server_address=addresses[0]
    @private_server_address=addresses[1]
    @server_port=55000
  end

  ## set suthentication info for the ossec manager in the selected environment
  # * +environment+ string
  # * +username+ string
  # * +password+ string
  def self.set_authentication_info(environment,username,password)
    environment=environment.to_sym if environment.is_a?String
    aws_settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
    throw "can't find this environment,'#{environment}'" if !aws_settings.has_key? environment
    environment_data= aws_settings[environment]
    driver = VaultDriver.from_secrets_file environment.to_s
    if environment_data.key?(:secrets)
        puts 'vault unlocked' if driver.unlock_vault(environment_data[:secrets][:vault][:keys]) == 200
    else
        puts 'no vault secrets file.'
    end
    driver.get_vault_status
    puts "vault is online" if driver.online && !driver.locked
    driver.put_json_in_path "secret/ossec-manager",{username: username,password: password}
  end


  def notify(message)
    if @notifire!=nil and @notifire.is_a?Notifire
      @notifire.notify 1,message
    end
  end

  ## gets the manager ip (can't use dns) for the reuested environment. return nil if none found.
  # * +environment+ - string. the environment name ("staging","sandbox" and so on)
  # * returns the ip string or nil if not found
  def self.get_ossec_manager_ip_for_environment(environment)
    aws_settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
    instances=AwsInstance.get_instances_with_filters   [
        { name: 'tag:Environment', values: [environment] },
        { name: 'tag:Service-Type', values: ["Ossec-Manager"] },
        { name: 'tag:Online', values: ["yes"] },
        { name: 'instance-state-name', values: ["running"] },],aws_settings
    return [instances[0].get_access_ip,instances[0].get_instance_private_ip_address]  if instances.length >0
    #return instances[0].get_instance_private_ip_address  if instances.length >0
    return nil
  end

  ## registering new agent with the server
  # * +agent_instance+ - AwsInstance - the instance to register
  def register_new_agent_with_instance (agent_instance)
    throw "not an aws instance!"  if !agent_instance.is_a?AwsInstance
    url_string="http://#{@server_address}:#{@server_port}/agents"
    url=URI(url_string)
    req = Net::HTTP::Post.new(url)
    agent_instance.notify  "registering new agent"
    res=Net::HTTP.start(url.hostname,url.port) do |http|
      req.basic_auth @username,@password
      req.body="name=#{agent_instance.name}&ip=#{agent_instance.aws_instance_data.private_ip_address}"
      http.request(req)
    end
    if res.code.to_i <=399
      agent_instance.notify "registered ok! getting key"
      client_data=JSON.parse(res.body)
      client_id=client_data['data']
      url_string="http://#{@server_address}:#{@server_port}/agents/#{client_id}/key"
      url=URI(url_string)
      req = Net::HTTP::Get.new(url)
      res=Net::HTTP.start(url.hostname,url.port) do |http|
        req.basic_auth @username,@password
        http.request(req)
      end
      if res.code.to_i<=399
        agent_instance.notify  "key for agent obtained! installing on agent..."
        client_key_data=JSON.parse(res.body)
        ssh_command="sudo echo \"y\" | sudo /var/ossec/bin/manage_agents -i #{client_key_data['data']}"
        s3_client=Helpers.create_aws_S3_client
        agent_instance.notify  "loading configuration for agent..."
        resp=s3_client.get_object({
          bucket: "btrz-aws-automation",
          key: "ossec/agent/ossec.conf"
          })
        xml_content=resp.body.read
        noko_xml=Nokogiri::XML(xml_content)
        noko_xml.css("ossec_config client server-ip").first.content=@private_server_address
        agent_instance.notify  "deploying configuration to agent, server ip=#{@private_server_address}"
        agent_instance.upload_data_to_file noko_xml.root.to_s,"/home/ubuntu/ossec.conf"
        agent_instance.notify "removing old keys"
        agent_instance.run_ssh_command "sudo rm /var/ossec/etc/client.keys"
        agent_instance.notify "updating configuration"
        agent_instance.run_ssh_command "sudo cp /home/ubuntu/ossec.conf /var/ossec/etc/ossec.conf && sudo chown root:ossec /var/ossec/etc/ossec.conf && sudo chmod 640 /var/ossec/etc/ossec.conf"
        answer=agent_instance.run_ssh_command ssh_command
        agent_instance.notify  "restarting agent..."
        agent_status=agent_instance.run_ssh_command "sudo /var/ossec/bin/ossec-control restart"
        if (answer.index( "Added") !=nil and agent_status.index( "Completed")!=nil)
          return true,{
            agent_key: client_key_data['data'],
            answer: answer,
            status: agent_status,
          }
        else
          return false,{
            agent_key: client_key_data['data'],
            answer: answer,
            status: agent_status,
          }
        end
      else
        return false, res.code
      end
    else
      agent_instance.notify "authentication error connecting to server #{@server_address} in #{@environment}"
      return false, res.code
    end
  end

  ## removing agent from  the server
  # * +agent_instance+ - AwsInstance - the instance to be removed
  def remove_agent_by_instance(agent_instance)
    remove_agent_by_name agent_instance.name
  end

  ## removes an agent by name
  # * +agent_name+ -  the agent name
  def remove_agent_by_name(agent_name)
    all_agents=list_all_agents['items']
    agent_id=nil
    all_agents.each do |item|
      if item['name']==agent_name
        agent_id=item['id']
      else
      end
      break if agent_id!=nil
    end
    return 404 if agent_id==nil
    return remove_agent_by_id agent_id
  end

  ## remove an agent by it's id
  # * +agent_id+ - the id code
  def remove_agent_by_id(agent_id)
    url_string="http://#{@server_address}:#{@server_port}/agents/#{agent_id}"
    url=URI(url_string)
    req = Net::HTTP::Delete.new(url)
    res=Net::HTTP.start(url.hostname,url.port) do |http|
      req.basic_auth @username,@password
      http.request(req)
    end
    return res.code.to_i
  end
  ## removes all agents
  def remove_all_agents
    agents_list=list_all_agents
    agents_list['items'].each do |item|
      remove_agent_by_id item['id'] if item['id']!="000"
    end
  end

  ## lists all current agents
  # returns list of agents json, and http code int
  def list_all_agents
    url_string="http://#{@server_address}:#{@server_port}/agents"
    url=URI(url_string)
    req = Net::HTTP::Get.new(url)
    res=Net::HTTP.start(url.hostname,url.port) do |http|
      req.basic_auth @username,@password
      http.request(req)
    end
    if res.code.to_i>399 then
      return nil,res.code.to_i
    else
      return (JSON.parse res.body)['data'],res.code.to_i
    end
  end
end
