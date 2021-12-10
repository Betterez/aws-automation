#!/usr/bin/ruby
require_relative 'betterez/Helpers'
require_relative 'betterez/SecretsManager'
require('open3')
require 'optparse'
sm_setup = {}

OptionParser.new do |opts|
  opts.banner = 'usage: delete_secrets_manager_key.rb [options]'
  opts.on('--repo REPO', 'github repository name') do |argument|
    sm_setup[:repo] = argument
  end
  opts.on('--env Environment', 'environment, sandbox or production') do |argument|
    sm_setup[:env] = argument
  end
  opts.on('--var VAR', 'secret key name to delete.') do |argument|
    sm_setup[:var] = argument
  end
end.parse!

raise OptionParser::MissingArgument if sm_setup[:repo].nil? || sm_setup[:repo] == ''
raise OptionParser::MissingArgument if sm_setup[:var].nil? || sm_setup[:var] == ''
raise OptionParser::MissingArgument if sm_setup[:env].nil? || sm_setup[:env] == ''

secrets_manager = SecretsManager.new
secrets_manager.repository = sm_setup[:repo]
secrets_manager.environment = sm_setup[:env]

code = secrets_manager.delete_secret_key(sm_setup[:var])
if code > 399
  puts "error - #{code}"
  exit 1
end
Helpers.log "Done deleting key name #{sm_setup[:var]} from #{sm_setup[:env]}"
exit 0
