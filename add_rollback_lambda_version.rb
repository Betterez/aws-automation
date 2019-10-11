require 'aws-sdk'

@region = 'us-east-1' 
@client = Aws::Lambda::Client.new(region: @region)

repo = @client.get_alias({
  function_name: "btrz-applet-loyalty",
  name: "latest"
})

puts "alias response"
puts repo