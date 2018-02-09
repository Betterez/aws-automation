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
lower_case_values={}
all_repos_names,code=driver.get_json(driver.all_repos_path)
throw vault error if code>399
all_repos_names["repos"].keys.each do |repository|
  lower_case_values.clear
  repo_data,code=driver.get_json("secret/#{repository}")
  #values=repo_data.keys
  repo_data.each do |key,value|
    lower_case_values[key.downcase]=value
  end
  puts "fixing service #{repository}"
  puts lower_case_values
  code=driver.put_json_for_repo(repository,lower_case_values,false)
  puts "posted with code #{code}"
  #puts "#{repository}:#{values}"
end
Helpers.log "done"
