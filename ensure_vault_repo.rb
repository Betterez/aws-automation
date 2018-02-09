#!/usr/bin/ruby
require_relative 'betterez/VaultDriver'
require_relative 'betterez/Helpers'
require_relative 'betterez/ELBClient'
require 'optparse'
settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
vault_setup={}
OptionParser.new do |opts|
  opts.banner = 'usage: ensure_vault_repo.rb [options]'
  opts.on('--repo REPO', 'github repository name') do |argument|
    vault_setup[:repo] = argument
  end
  opts.on('--env Environment', 'vaulting environment, staging sandbox or production') do |argument|
    vault_setup[:env] = argument
  end
end.parse!

fail OptionParser::MissingArgument if vault_setup[:repo].nil? || vault_setup[:repo] == ''
fail OptionParser::MissingArgument if vault_setup[:env].nil? || vault_setup[:env] == ''
vault_setup[:env]=vault_setup[:env].to_sym

if !settings.has_key? vault_setup[:env]
  puts "no values for #{vault_setup[:env]}"
  exit 1
end
if !settings[vault_setup[:env]].has_key? :vault
  puts "no vault value in #{vault_setup[:env]}"
  exit 1
end

vault_settings=settings[vault_setup[:env]][:vault]
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
code=driver.ensure_repo_listing vault_setup[:repo]
Helpers.log "done with code #{code}"
puts "loading all repos..."
data,code=driver.list_all_registered_repos
throw "code error:#{code}" if code >399
puts "repos data: #{data}"
