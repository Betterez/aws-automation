require 'aws-sdk'
require 'optparse'

@region = 'us-east-1' 
@client = Aws::Lambda::Client.new(region: @region)

runner_options = { timeout: 3700, ignore_errors: false }
STDOUT.sync = true
OptionParser.new do |opts|
  opts.banner = "usage #{__FILE__} [options]"
  opts.on('--repo REPOSITORY', 'find in the claudia.json file of the project') do |argument|
    runner_options[:repo] = argument
  end
end.parse!
raise OptionParser::MissingArgument if runner_options[:repo].nil? || (runner_options[:repo] == '')

repo = @client.get_alias({
  function_name: runner_options[:repo],
  name: "previous"
})

puts "alias response"
puts repo

resp = @client.update_alias({
  function_name: runner_options[:repo], 
  function_version: repo['function_version'],
  name: "latest", 
})

puts "update alias response"
puts resp