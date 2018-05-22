#!/usr/bin/ruby
require_relative './betterez/VaultDriver'
require 'optparse'
require 'open3'

runner_options={}
OptionParser.new do |opts|
  opts.banner="usage #{__FILE__} [options]"
  opts.on("--env ENVIRONMENT","environment type - staging,sandbox,production") do |argument|
    runner_options[:environment]=argument
  end
  opts.on("--command COMMAND","command to execute") do |argument|
    runner_options[:command]=argument
  end
  opts.on("--repo REPOSITORY","repository to run against") do |argument|
    runner_options[:repo]=argument
  end
  opts.on("--settings SETTINGS","settings folder location") do |argument|
    runner_options[:settings]=argument
  end
end.parse!
raise OptionParser::MissingArgument if (  (runner_options[:environment] == nil )||( runner_options[:environment] == "" ) )
raise OptionParser::MissingArgument if (  (runner_options[:command] == nil )||( runner_options[:command] == "" ) )
raise OptionParser::MissingArgument if (  (runner_options[:repo] == nil )||( runner_options[:repo] == "" ) )


puts "for environment #{runner_options[:environment]}"
puts "running: #{runner_options[:command]}"
puts "=========================="
setting_file="./settings/secrets.json"
setting_file=runner_options[:settings]+"/settings/secrets.json" if !runner_options[:settings].nil?
driver = VaultDriver.from_secrets_file(runner_options[:environment],setting_file)
vars= driver.get_system_variables_for_service(runner_options[:repo])
if vars.nil? || vars==""
  puts "no vars for #{runner_options[:repo]} in #{runner_options[:environment]}"
  exit 0
# else
#   puts vars
end
Open3.popen3("#{vars} #{runner_options[:command]}") do |stdin,stdout,stderr|
  if !stderr.nil? && stderr.read!=""
    puts "error:#{stderr.read }"
  else
    puts stdout.read
  end
end
