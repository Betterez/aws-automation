#!/usr/bin/ruby
require_relative '../betterez/VaultDriver'
require_relative '../betterez/Helpers'

if ARGV.length!=2
  puts "usage is #{__FILE__} service environment"
  exit 1
end

service = ARGV[0]
environment = ARGV[1]
settings_file='./settings/secrets.json'


puts "for environment #{environment}"
driver = VaultDriver.from_secrets_file environment, settings_file
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
puts "vault info:#{driver.get_vault_info}"
puts "driver online status #{driver.get_vault_status}"
data, code=driver.get_json("secret/#{service}")
if code<399
  puts data
end
# puts driver.get_system_variables_for_service "connex2"
puts "================================================\n"
