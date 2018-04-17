#!/usr/bin/ruby
# updates a value into vault
require_relative 'betterez/Helpers'
require_relative 'betterez/VaultDriver'
require('open3')
require 'optparse'
settings = Helpers.load_json_data_to_hash('settings/aws-data.json')

vault_setup={append: false}

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
  opts.on('--append', 'add or update current vaules without removeing existing ones') do
    vault_setup[:append] = true
  end
end.parse!

fail OptionParser::MissingArgument if vault_setup[:repo].nil? || vault_setup[:repo] == ''
fail OptionParser::MissingArgument if vault_setup[:vars].nil? || vault_setup[:vars] == ''
fail OptionParser::MissingArgument if vault_setup[:env].nil? || vault_setup[:env] == ''

if !settings.has_key? vault_setup[:env].to_sym
  puts "can't find #{vault_setup[:env]}."
  exit 1
end
puts "appending to existing values" if vault_setup[:append]
puts "*******replacing ********* existing values" if !vault_setup[:append]
if(settings[vault_setup[:env].to_sym].has_key?(:vault) == false)
  puts "no vault settings for this environment!"
  exit 1
end

exp=Regexp.new('([\w]+)=([\w!@#$%^&\/*\(\)\~\+\\\:.;-]+)')
param_names=[]
res=vault_setup[:vars].scan(exp)
params={}
res.each do |pair|
  params[pair[0].downcase]=pair[1]
  param_names.push(pair[0])
end
if params=={}
  puts "empty params, exits"
  exit 1
end
vault_settings=settings[vault_setup[:env].to_sym][:vault]
Helpers.log "updating #{vault_setup[:env]} on #{vault_settings[:address]}"
Helpers.log "Connecting ...."
driver=VaultDriver.new(vault_settings[:address],vault_settings[:port],vault_settings[:token])
driver.get_vault_status
if(!driver.online)
  puts "driver off line"
  exit 1
end
Helpers.log "Connected"
Helpers.log "updating params: #{params}"
results=nil
code=nil
if vault_setup[:repo]=="all" then
  puts "updating all"
  results=driver.put_json_for_all_repos(params,vault_setup[:append])
else
  puts "updating #{vault_setup[:repo]}"
  code=driver.put_json_for_repo(vault_setup[:repo],params,vault_setup[:append])
end

if(code != nil && code >399)
  puts "Error #{code} settings data to #{vault_setup[:env]} vault."
  exit 1
else
  if results != nil
    puts "results are #{results}"
    results.keys.each do |key|
      if results[key]>399
        puts "Error #{results[key]} when setting #{key}"
        exit 1
      end
    end
    if vault_setup[:repo]=="all"
      test_repo="betterez-app"
    else
      test_repo=vault_setup[:repo]
    end
    # data,code=driver.get_json("secret/#{test_repo}")
    # param_names.each do |param_name|
    #   puts "value for #{param_name} is #{data[param_name]}"
    # end
  end
end
puts "done updating"
