#!/usr/bin/ruby
require_relative 'betterez/VaultDriver'
require_relative 'betterez/Helpers'
require_relative 'betterez/ELBClient'
settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
if ARGV.length==0
  puts "please select an environment"
  exit 1
end
location=ARGV[0].to_sym
if !settings.has_key? location
  puts "no values for #{location}"
  exit 1
end
if !settings[location].has_key? :vault
  puts "no vault value"
  exit 1
end
vault_settings=settings[location][:vault]
driver=VaultDriver.new(vault_settings[:address],vault_settings[:port],vault_settings[:token])
driver.get_vault_status
if !driver.online
  puts "not online"
  exit 1
end
if driver.locked
  puts "driver locked "
  exit 1
end
if !driver.authorized
  puts  "bad token"
  exit 1
end
data,code=driver.get_json(driver.all_repos_path)
values_hash={}
data["repos"].keys.each do |repository|
  data,code=driver.get_json("secret/#{repository}")
  values=data.keys
  puts "repo #{repository}\n"
  values_hash.clear
  is_there_a_copy=false
  values.each do |value|
    if values_hash.has_key?(value.downcase)
      puts "\tvalue #{value} exists!"
      is_there_a_copy=true
    else
      values_hash[value.downcase]=1
    end
  end
  puts "repo data:\n----------------------\n#{data.to_json}\n\n" if is_there_a_copy
end
Helpers.log "done"
