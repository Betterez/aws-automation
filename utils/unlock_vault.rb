#!/usr/bin/ruby
require_relative '../betterez/VaultDriver'
require_relative '../betterez/Helpers'
environments=["production","staging","sandbox"]

environments.each do |environment|
  puts "for environment #{environment}"
  puts "================================================\n"
  driver=VaultDriver.from_secrets_file(environment,"settings/secrets.json")
  puts "vault online? :#{driver.get_vault_status}"
  puts "vault info:#{driver.get_vault_info}"
  if !driver.online || driver.locked
    puts "vault is locked, opening..."
    keys_data=Helpers.load_json_data_to_hash "settings/secrets.json"
    keys_data[environment.to_sym][:vault][:keys]
    puts driver.unlock_vault keys_data[environment.to_sym][:vault][:keys]
  end
  puts "vault info:#{driver.get_vault_info}"
  puts "driver online status #{driver.get_vault_status}"
  puts ""
end
