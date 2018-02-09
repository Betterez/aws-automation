require 'json'

class CommandParser
  attr_accessor(:command)
  attr_accessor(:environment,:service_type)
  attr_reader(:additional_servers)
  
  def initialize ()
    clear!
    @environment="staging"
    @service_type="ec2"
  end
  
  def command=(new_command)
    if new_command!=nil
      @command=new_command
    end
    result=JSON.parse(@command,{:symbolize_names => true})
    if result[:environment] !=nil
      @environment=result[:environment]
    end
    if result[:service_type] !=nil
      @service_type=result[:service_type]
    end
  end  
  
  def getServersData
    servers=[]  
    if @command!=nil 
      result=JSON.parse(@command,{:symbolize_names => true})
      if result[:servers]
        servers=result[:servers]
      end
    end
    if @additional_servers 
      servers.push(@additional_servers).flatten!
    end
    if(servers.length) then
      populate_servers(servers)
    end
    return servers
  end
  
  def service_type=(type)
    if type=="ec2" || type == "ecs"
      @service_type=type
    else
      raise ArgumentError.new("bad service type")
    end
  end
  
  def populate_servers(servers)
    servers.each do |server|
      if(server[:host_port]==nil)
        server[:host_port]=3000
      end
      if server[:server_type] == nil
        server[:server_type]=:default
      end
    end
  end
  
  def checkLegalServer(server_data)
    if server_data == nil then
      return false
    end
    if !server_data[:serviceName] || !server_data[:instance_private_ip]
      return false
    end
    if server_data[:serviceName].strip=="" ||server_data[:instance_private_ip].strip==""
      return false
    end
    return true
  end
  
  def addAdditionalServer (serverData)
    if checkLegalServer(serverData) then
      @additional_servers.push(serverData)
    else
      raise ArgumentError.new("missing info")
    end
  end

  def add_additional_servers(servers_data)
    servers_data.each do |server_data|
      addAdditionalServer(server_data)
    end
  end

  def generateTasksData
    tasks=[]
    servers=getServersData
    if servers==nil
      return nil
    end
  end
  
  def clear!
    @command=nil
    @additional_servers=[]
  end
  
  private  :populate_servers 
end
