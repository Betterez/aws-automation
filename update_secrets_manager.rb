#!/usr/bin/ruby
# updates a value into secrets manager
require_relative 'betterez/Helpers'
require_relative 'betterez/SecretsManager'
require('open3')
require 'optparse'
require 'digest'

sm_setup = { append: false }

OptionParser.new do |opts|
  opts.banner = 'usage: update_secrets_manager.rb [options]'
  opts.on('--repo REPO', 'github repository name') do |argument|
    sm_setup[:repo] = argument
  end
  opts.on('--env Environment', 'secrets manager environment, sandbox or production') do |argument|
    sm_setup[:env] = argument
  end
  opts.on('--vars VARS', 'Variables to set, no spaces,name=value format, separated by commas.') do |argument|
    sm_setup[:vars] = argument
  end
  opts.on('--append', 'add or update current values without removing existing ones') do
    sm_setup[:append] = true
  end
end.parse!

raise OptionParser::MissingArgument if sm_setup[:repo].nil? || sm_setup[:repo] == ''
raise OptionParser::MissingArgument if sm_setup[:vars].nil? || sm_setup[:vars] == ''
raise OptionParser::MissingArgument if sm_setup[:env].nil? || sm_setup[:env] == ''

puts 'appending to existing values' if sm_setup[:append]
puts '*******replacing ********* existing values' unless sm_setup[:append]

exp = Regexp.new('([\w]+)=([\w!@#$%^&\/*\(\)\~\+\\\:.;-]+)')
param_names = []
res = sm_setup[:vars].scan(exp)
params = {}
res.each do |pair|
  params[pair[0].downcase] = pair[1]
  param_names.push(pair[0])
end
if params == {}
  puts 'empty params, exits'
  exit 1
end

secrets_manager = SecretsManager.new
secrets_manager.repository = sm_setup[:repo]
secrets_manager.environment = sm_setup[:env]

results = nil
code = nil

puts "updating #{sm_setup[:repo]}"
code = secrets_manager.set_secret_value(params, sm_setup[:append])
puts "update done with #{code}"

if !code.nil? && code > 399
  puts "Error #{code} setting data to #{sm_setup[:env]} secrets manager."
  exit 1
end
puts 'done updating'
