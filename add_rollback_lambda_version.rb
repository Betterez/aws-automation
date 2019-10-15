require 'aws-sdk'

@region = 'us-east-1' 
@client = Aws::Lambda::Client.new(region: @region)

runner_options = { timeout: 3700, ignore_errors: false }
STDOUT.sync = true
OptionParser.new do |opts|
  opts.banner = "usage #{__FILE__} [options]"
  opts.on('--repo FUNTION_NAME', 'find in the claudia.json file of the project') do |argument|
    runner_options[:function_name] = argument
  end
end.parse!
raise OptionParser::MissingArgument if runner_options[:function_name].nil? || (runner_options[:function_name] == '')

repo = @client.get_alias({
  function_name: runner_options[:function_name]
  name: "previous"
})

puts "alias response"
puts repo

resp = @client.update_alias({
  function_name: runner_options[:function_name], 
  function_version: repo['function_version'],
  name: "latest", 
})

puts "update alias response"
puts resp