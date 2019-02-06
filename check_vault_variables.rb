#!/usr/bin/ruby
require_relative 'betterez/VaultDriver'
require_relative 'betterez/Helpers'
require_relative 'betterez/ELBClient'
settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
if ARGV.empty?
  puts 'please select an environment'
  exit 1
end
location = ARGV[0].to_sym
unless settings.key? location
  puts "no values for #{location}"
  exit 1
end
unless settings[location].key? :vault
  puts 'no vault value'
  exit 1
end
vault_settings = settings[location][:vault]
driver = VaultDriver.new(vault_settings[:address], vault_settings[:port], vault_settings[:token])
driver.get_vault_status
unless driver.online
  puts 'not online'
  exit 1
end
if driver.locked
  puts 'vault driver locked.'
  exit 1
end
unless driver.authorized
  puts 'bad authorization token'
  exit 1
end
data, code = driver.get_json(driver.all_repos_path)
data['repos'].keys.each do |key|
  data, code = driver.get_json("secret/#{key}")
  values = data.keys
  puts "#{key}:\r\n----------------------------"
  values.each do |value|
    puts value if value.index('aws') != -1
  end
  puts "\r\n"
  # puts "#{key}:#{values}" if values.include?
end
Helpers.log 'done'
