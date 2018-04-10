#!/usr/bin/ruby
require_relative './betterez/VaultDriver'
require_relative './betterez/Helpers'
require_relative './betterez/AwsInstance'
require_relative './betterez/Syslogger'

service ="btrz-worker-exports"
service ="betterez-app"
environment = "sandbox"
# environment = "production"
# environment = "staging"
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
  instance_services.push(instance.get_tag_by_name("Repository"))
end
Helpers.log("Done listing active services in #{environment}")
instance_services.each do |instance_service|
  next if instance_service.nil? or instance_service.strip==""
  data, code=driver.get_json("secret/#{instance_service}")
  if code>399 or data.nil?
    puts "Service #{instance_service} got #{code} with #{data}, moving on..."
    next
  end
  if data.has_key?("logentries_token")
    puts "adding syslog to: service #{instance_service}"
    driver.put_json_for_repo(instance_service,{"logentries_syslog_token":data['logentries_token']},true)
  else
    puts "service #{instance_service} does not have a token!"
  end
end



# puts driver.get_system_variables_for_service "connex2"
puts "================================================\n"
