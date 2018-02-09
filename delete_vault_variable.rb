#!/usr/bin/ruby
require_relative 'betterez/Helpers'
require_relative 'betterez/VaultDriver'
require('open3')
require 'optparse'
settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
vault_setup={}

OptionParser.new do |opts|
  opts.banner = 'usage: update_vault.rb [options]'
  opts.on('--repo REPO', 'github repository name') do |argument|
    vault_setup[:repo] = argument
  end
  opts.on('--env Environment', 'vaulting environment, staging sandbox or production') do |argument|
    vault_setup[:env] = argument
  end
  opts.on('--vars VARS', 'Variables to set, no spaces,name=value format, separated by commas.') do |argument|
    vault_setup[:vars] = argument
  end
end.parse!

fail OptionParser::MissingArgument if vault_setup[:repo].nil? || vault_setup[:repo] == ''
fail OptionParser::MissingArgument if vault_setup[:vars].nil? || vault_setup[:vars] == ''
fail OptionParser::MissingArgument if vault_setup[:env].nil? || vault_setup[:env] == ''

vault_settings=settings[vault_setup[:env].to_sym][:vault]
driver=VaultDriver.new(vault_settings[:address],vault_settings[:port],vault_settings[:token])
driver.get_vault_status
if(!driver.online)
  puts "driver off line"
  exit 1
end
code=driver.delete_value(vault_setup[:repo],vault_setup[:vars])
if(code>399)
  puts "error - #{code}"
  exit 1
end
Helpers.log "Done deleting value #{vault_setup[:vars]} from #{vault_setup[:env]}"
exit 0
