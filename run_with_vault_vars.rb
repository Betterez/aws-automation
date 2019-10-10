#!/usr/bin/ruby
require_relative './betterez/VaultDriver'
require 'optparse'
require 'mixlib/shellout'

runner_options = { timeout: 3700, ignore_errors: false }
STDOUT.sync = true
OptionParser.new do |opts|
  opts.banner = "usage #{__FILE__} [options]"
  opts.on('--env ENVIRONMENT', 'environment type - staging,sandbox,production') do |argument|
    runner_options[:environment] = argument
  end
  opts.on('--command COMMAND', 'command to execute') do |argument|
    runner_options[:command] = argument
  end
  opts.on('--timeout TIMEOUT', 'tine in seconds') do |argument|
    runner_options[:timeout] = argument
  end
  opts.on('--repo REPOSITORY', 'repository to run against') do |argument|
    runner_options[:repo] = argument
  end
  opts.on('--settings SETTINGS', 'settings folder location') do |argument|
    runner_options[:settings] = argument
  end
  opts.on('--ignore_errors', 'if set, will ignore errors') do
    runner_options[:ignore_errors] = true
  end
  opts.on('--append_vars', 'if set, will append found vault vars to given command') do
    runner_options[:append_vars] = true
  end
end.parse!
raise OptionParser::MissingArgument if runner_options[:environment].nil? || (runner_options[:environment] == '')
raise OptionParser::MissingArgument if runner_options[:command].nil? || (runner_options[:command] == '')
raise OptionParser::MissingArgument if runner_options[:repo].nil? || (runner_options[:repo] == '')

puts "for environment #{runner_options[:environment]}"
puts "running: #{runner_options[:command]}"
puts '=========================='
secrets_file = 'settings/secrets.json'
unless runner_options[:settings].nil?
  runner_options[:settings] += File::SEPARATOR if runner_options[:settings][runner_options[:settings].length - 1] != File::SEPARATOR
  puts "using alternated file in #{runner_options[:settings]}"
  secrets_file = runner_options[:settings] + 'settings/secrets.json'
end
driver = VaultDriver.from_secrets_file(runner_options[:environment], secrets_file)
vars = driver.get_system_variables_for_service(runner_options[:repo])
if vars.strip == ''
  puts "no vars for this repo, exiting\r\n"
  exit 1
else
  puts 'vars found for repo. executing command...'
end
if runner_options[:append_vars]
  run_command = "#{runner_options[:command]}#{vars}"
else
  run_command = "#{vars} #{runner_options[:command]}"
end
so = Mixlib::ShellOut.new(run_command, timeout: runner_options[:timeout])
so.live_stream = $stdout
so.run_command
out = so.stdout
unless runner_options[:ignore_errors]
  command_error = so.stderr.strip!
  puts ''
  if command_error.nil? || command_error.empty?
    puts  'command executed successfully!'
  else
    throw command_error
  end
end
