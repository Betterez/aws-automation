#!/usr/bin/ruby
require_relative './betterez/VaultDriver'
require 'optparse'
require 'mixlib/shellout'

runner_options={}
STDOUT.sync = true
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
secrets_file="settings/secrets.json"
if (!runner_options[:settings].nil? )
  runner_options[:settings]+=File::SEPARATOR if runner_options[:settings][runner_options[:settings].length-1]!=File::SEPARATOR
  puts "using alternated file in #{runner_options[:settings]}"
  secrets_file=runner_options[:settings]+"settings/secrets.json"
end
driver = VaultDriver.from_secrets_file(runner_options[:environment],secrets_file)
vars= driver.get_system_variables_for_service(runner_options[:repo])
if vars.strip==""
  puts "no vars for this repo, exiting\r\n"
  exit 1
else
  puts  "vars found for repo. executing command..."
end
run_command="#{vars} #{runner_options[:command]}"
so = Mixlib::ShellOut.new(run_command)
so.live_stream = $stdout
so.run_command
out = so.stdout
# Open3.popen3(run_command) do |stdin,stdout,stderr,wait_thr|
#   exit_status = wait_thr.value
#   std_err_desc=stderr.read.strip
#   if !stderr.nil? && std_err_desc!="" && exit_status!=0
#     puts "error:#{std_err_desc}"
#     puts stdout.read
#     puts "terminating with error"
#     exit 1
#   else
#     puts "\r\ncompleted!\r\n\r\n"
#     puts stdout.read
#   end
# end
