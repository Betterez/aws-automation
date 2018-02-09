#!/usr/bin/ruby

require 'open3'
require 'optparse'
require 'yaml'
require_relative 'betterez/AwsInstance'
require_relative 'utils/HashOverrider'


authentication = Helpers.load_json_data_to_hash('settings/authentication.json')
overrider=HashOverrider.new

image_settings = { create_image: true}
force_create = false
OptionParser.new do |opts|
    opts.banner = "usage: #{__FILE__} [options]"
    opts.on('--create_image CREATE', 'create an image if not exists') do
        image_settings[:create_image]=true
    end
    opts.on('--service_file FILE', 'the yml service file') do |argument|
        image_settings[:service_file]=argument
    end
    opts.on('--env ENVIRONMENT', 'production,staging or sandbox') do |argument|
        image_settings[:environment] = argument
    end
    opts.on('--pp PACKER_PATH', 'where packer files are located.') do |argument|
        image_settings[:packer_path] = argument
    end
end.parse!

raise OptionParser::MissingArgument if image_settings[:environment].nil? || image_settings[:environment] == ''
raise OptionParser::MissingArgument if image_settings[:packer_path].nil? || image_settings[:packer_path] == ''
raise OptionParser::MissingArgument if image_settings[:service_file].nil? || image_settings[:service_file] == ''

if !File.exists?(image_settings[:service_file])
  puts "service file #{image_settings[:service_file]} doesn't exists!"
  exit 1
end
service_data=YAML.load_file(image_settings[:service_file])
overrider.override_hash! service_data,image_settings[:environment]

puts "checking image #{service_data["machine"]["image"]}"
image_id=AwsInstance.get_ami_id(service_data["machine"]["image"])
if (image_id!=nil)
  puts "image found for #{service_data["machine"]["image"]}: #{image_id}"
  exit 0
end
puts "image does not exist"
exit 1 if !image_settings[:create_image]

packer_file="#{image_settings[:packer_path]}/#{service_data["machine"]["image"]}.json"
throw "can't find packer file #{packer_file}" if !File.exists?(packer_file)
puts  "creating image..."
packer_command="cd #{image_settings[:packer_path]} && packer build -var 'aws_access_key=#{authentication[:access_key_id]}' -var 'aws_secret_key=#{authentication[:secret_access_key]}' #{service_data["machine"]["image"]}.json"
stdin,stdout,stderr,wait_thr=Open3.popen3(packer_command)
if wait_thr.value!=0
  puts "error: running #{packer_command}"
  stderr.each do |err|
    puts err
  end
  exit 1
end
stdout.each do |line|
  puts line
end
