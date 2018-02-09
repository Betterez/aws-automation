require 'net/ssh'
require 'net/scp'
require 'json'
require 'net/http'
require_relative 'AwsInstance'
require_relative 'Helpers'
require "redis"


class BetterezAppTester
  attr_accessor :servers
  attr_accessor :delay_time
  attr_accessor :keys_path
  def initialize(settings)
    @servers=[]
    @settings=settings
    @redis = Redis.new()
  end
  def load_application_servers
    filters=[
      { name: 'tag:Repository', values: ["betterez-app"] },
      { name: 'tag:Service-Type', values: ["http"] },
      { name: 'tag:Environment', values: ["production"] },
      { name: 'tag:Online', values: ["yes"] },
      { name: 'instance-state-name', values: ["running"] },
    ]
    loaded_servers=AwsInstance.get_instances_with_filters(filters,@settings)
    loaded_servers.each do |server|
      server.host_port=3000
    end
    loaded_servers
  end
  def add_servers(servers)
    return if servers ==nil
    if servers.is_a?(Array)
      servers.each do |server|
        @servers.push(server) if server.is_a?(AwsInstance)
      end
    end
  end

  def check_server_availability(server)
    url="http://"+server.get_access_ip+"/healthcheck"
    uri=URI(url)
    req = Net::HTTP::Get.new(uri)
    begin
      res = Net::HTTP.start(uri.hostname, server.host_port, :read_timeout => 5) {|http|
          http.request(req)
        }
        return res.code.to_i <400
    rescue
      return false
    end
  end

  def check_servers_availability
    @servers.each do |server|
      if check_server_availability server
        @redis.hset "servers",server.get_access_ip,"server is online!"
      else
        @redis.hset "servers",server.get_access_ip,"server is offline!"
      end
    end
  end

  def send_alarm(server)
    sns_client = Aws::SNS::Client.new(
      region: "us-east-1",
      credentials: Helpers.create_aws_authentication_token)
    #server="10.1.2.2"
    sns_client.set_sms_attributes({
      attributes:{
        "DefaultSenderID"=>"betterez"
      }
      })
    sns_client.publish({
      phone_number: "+972545944489",
      message: "betterez-app server is down @ #{server}",
      subject: "betterez",
      })
  end

  def maintain_servers
    while true do
      begin
        servers=load_application_servers
      rescue
        servers=nil
      end
      if servers!=nil
        @servers=servers
      end
      @servers.each do |server|
        if check_server_availability server
          @redis.hset "servers",server.get_access_ip,"#{Time.now} server is online!"
        else
          loops=0
          while (loops < 3) do
            @redis.hset "servers",server.get_access_ip,"#{Time.now} server is offline!"
            @redis.hset "servers-restarts",server.get_access_ip,"#{Time.now} server is offline!"
            puts server.run_ssh_command "sudo service betterez-app restart"
            puts server.run_ssh_command "sudo service betterez-app restart"
            loops+=1
            sleep 20
            if check_server_availability server
              Helpers.log "restarted ok! "
              break
            end
          end
          send_alarm server if loops==3
        end
      end
      sleep 10
    end
  end

end
