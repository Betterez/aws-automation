#!/usr/bin/ruby
require_relative '../betterez/VaultDriver'
require_relative '../betterez/Helpers'
require_relative '../betterez/AwsInstance'
require_relative '../betterez/Syslogger'

service ="btrz-worker-exports"
service ="betterez-app"
environment = "sandbox"
#environment = "staging"
#environment = "production"
settings_file='./settings/secrets.json'


puts "for environment #{environment}"
driver = VaultDriver.from_secrets_file environment, settings_file
aws_settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
#puts "loading servers for service #{service} in #{environment}"
aws_instances=AwsInstance.get_instances_with_filters([
                                                           { name: 'tag:Environment', values: [environment] },
                                                           { name: 'instance-state-name', values: ['running'] }
                                                       ], aws_settings)
if aws_instances.length==0
  puts "no instyances found"
  exit 1
end
puts "vault status:#{driver.get_vault_status}"
if !driver.online || driver.locked
  puts 'vault is locked, opening...'
  keys_data = Helpers.load_json_data_to_hash settings_file
  if keys_data.nil?
    throw "keys_data is nil"
  end
  keys_data[environment.to_sym][:vault][:keys]
  puts driver.unlock_vault keys_data[environment.to_sym][:vault][:keys]
end
# data, code=driver.get_json("secret/#{service}")
# if code<399
#   puts "Logentry token: #{data['logentries_token']}"
# end
instance_services=[]
aws_instances.each do |instance|
  if !instance.get_tag_by_name("Repository").nil?&&instance.get_tag_by_name("Repository").strip!=""
    instance_services.push(instance.get_tag_by_name("Repository"))
  end
  logger=Syslogger.new(instance,driver,instance.get_tag_by_name("Repository"))
  puts logger.add_record_to_rsyslog
end

Helpers.log("Done listing active services in #{environment}")
# service_json_to_create=[]
# instance_services.each do |instance_service|
#   next if instance_service.nil? or instance_service.strip==""
#   data, code=driver.get_json("secret/#{instance_service}")
#   if code>399 or data.nil?
#     service_hash={instance_service=>{"service_name"=>instance_service,"environments"=>[environment],"path"=>"/","use_log_entries"=>true}}
#     service_json_to_create.push(service_hash)
#     puts "Service #{instance_service} got #{code} with #{data}, moving on..."
#     next
#   end
#   if data.has_key?("logentries_token")
#     puts "adding syslog to: service #{instance_service}"
#     driver.put_json_for_repo(instance_service,{"logentries_syslog_token":data['logentries_token']},true)
#
#   else
#     service_hash={instance_service=>{"service_name"=>instance_service,"environments"=>[environment],"path"=>"/","use_log_entries"=>true}}
#     service_json_to_create.push(service_hash)
#     puts "service #{instance_service} does not have a token!"
#   end
# end
# if instance_services.length>0
#   dump_file=open("./dump/services.json","w")
#   service_json_to_create.each_with_index do |service_hash,index|
#     if index==(service_json_to_create.length-1)
#       dump_file.write(service_hash.to_json[1,service_hash.to_json.length])
#     else
#       dump_file.write("#{service_hash.to_json[0,service_hash.to_json.length-1]},\r\n")
#     end
#   end
# end



# puts driver.get_system_variables_for_service "connex2"
puts "================================================\n"
