require 'net/ssh'
require 'net/scp'
# Generate nginx configuration file.
# can also upload the file through ssh and scp
class NginxConfigurator
  # initialize, with an optional server name.
  ROOT_NAME="root_app"
  def initialize(server_configuration=nil)
    if server_configuration!=nil then
      @server_name=server_configuration[:server_name]
    else
      @server_name="load_balancer"
    end
  end
  # generates a configuration file.
  # * configurationData [:tasks] is the tasks list
  # * configurationData [:lb] is the load balance configuration
  def generateConfigData(configurationData)
    if !check_tasks_validity(configurationData[:tasks])
      raise ArgumentError.new("Bad tasks configuration")
    end
    serverOutput="server {
    listen 80 default_server;
    listen [::]:80 default_server ipv6only=on;
    root /usr/share/nginx/html;
	  client_max_body_size 100m;
    index index.html index.htm;
	  large_client_header_buffers 4 40k;
    server_name #{@server_name};\n"
    loadBalancing={}
    configurationData[:tasks].each do |task|
      if task[:serviceName] == nil then
        next
      end
      if !loadBalancing.has_key?(task[:serviceName]) then
        loadBalancing[task[:serviceName]]=[];
      end
      if task[:filtered] == true then
        loadBalancing[task[:serviceName]].push("server #{task[:instance_private_ip]}:#{task[:host_port]} weight=0;")
      else
        loadBalancing[task[:serviceName]].push("server #{task[:instance_private_ip]}:#{task[:host_port]};")
      end
    end
    upstreamOutput=""
    loadBalancing.each do |name,entry|
      if name == "/" then
        upstreamOutput+="upstream #{NginxConfigurator::ROOT_NAME} {\n"
      else
        upstreamOutput+="upstream #{name} {\n"
      end
      entry.each do |uri|
        upstreamOutput+=uri+"\n"
      end
      upstreamOutput+="}\n"
      if name == "/" then
        serverOutput+="location / {"
      else
        serverOutput+="location /#{name}/ {"
      end
      if name == "/" then
        serverOutput+="\nproxy_pass http://#{NginxConfigurator::ROOT_NAME};"
      else
        serverOutput+="\nproxy_pass http://#{name};"
      end
      serverOutput+="\n proxy_set_header Host $host; \n proxy_set_header X-Real-IP $remote_addr; \n }\n"
    end
    serverOutput+="}"
    return "### Created at #{Time.new()} ###
    ### automated nginx configuration ###
    #{upstreamOutput}
    #{serverOutput}

    ### betterez inc.
    "
  end

  # generates configuration and saves it to a file.
  def generateConfigurationToFile(configuration,filePath)
    conf=generateConfigData(configuration)
    file=File.new(filePath,"w")
    file.write(conf)
    file.close
  end
  # generages and upload nginx configuration
  def uploadNewConfigurations(configurationData)
    conf=generateConfigData(configurationData)
    Net::SSH.start(configurationData[:lb]["server_ip"], "ubuntu", keys: configurationData[:lb]["keys"]) do |ssh|
      ssh.scp.upload!(StringIO.new(conf),"/home/ubuntu/nginx.conf")
      ssh.exec("sudo mv /home/ubuntu/nginx.conf /etc/nginx/sites-available/default && sudo nginx -s reload")  do |channel, stream, data|
      end
      ssh.exec("sudo nginx -s reload") do |channel, stream, data|
      end
    end
    conf
  end

  def check_tasks_validity(tasks)
    ips=[]
    tasks.each do |task|
      if ips.include?(task[:instance_private_ip])
        return false
      else
        ips.push(task[:instance_private_ip])
      end
    end
    return true
  end

private :check_tasks_validity
end
