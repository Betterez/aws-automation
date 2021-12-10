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
end.parse!

raise OptionParser::MissingArgument if sm_setup[:repo].nil? || sm_setup[:repo] == ''
raise OptionParser::MissingArgument if sm_setup[:env].nil? || sm_setup[:env] == ''

secrets_manager = SecretsManager.new
secrets_manager.repository = sm_setup[:repo]
secrets_manager.environment = sm_setup[:env]

secrets_manager.remove_repo_secrets

Helpers.log "Done deleting the repo secrets #{sm_setup[:repo]} from #{sm_setup[:env]}"
exit 0
