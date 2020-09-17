#!/usr/bin/ruby
require_relative 'betterez/ServerCreator'
require_relative 'betterez/Notifire'
require_relative 'betterez/Helpers'
require_relative 'utils/HashOverrider'
require('open3')
require 'optparse'
require 'yaml'

aws_setup_data = Helpers.load_json_data_to_hash('settings/aws-data.json')
secrets = Helpers.load_json_data_to_hash('settings/secrets.json')
if secrets
  aws_setup_data.keys.each do |key|
    next if !secrets.key?key
    aws_setup_data[key][:secrets]=secrets[key]
  end
end
STDOUT.sync = true
service_settings = { build_number: "0",branch_name: "master",
  service_file: "service.yml",dont_push_to_lb: false,
  debug: false, ami: false,offline_mode: false
}
force_create = false
OptionParser.new do |opts|
    opts.banner = 'usage: create_server.rb [options]'
    opts.on('--env ENVIRONMENT', 'production,staging or sandbox') do |argument|
        service_settings[:environment] = argument
    end
    opts.on('--build_number BUILD_NUMBER', 'external build number') do |argument|
        service_settings[:build_number] = argument
    end
    opts.on('--offline_mode', 'set online tag to no, to avoid reporting') do |_argument|
        service_settings[:offline_mode] = true
    end
    opts.on('--force_create', 'always create a new server.') do |_argument|
        force_create = true
    end
    opts.on('--dont_push', 'dont push the instances to the elb/alb.') do |_argument|
        service_settings[:dont_push_to_lb] = true
    end
    opts.on('--servers_count COUNT', 'number of servers to create') do |argument|
        service_settings[:servers_count] = argument.to_i
    end
    opts.on('--service_file SERVICE_FILE', 'yml service file') do |argument|
        service_settings[:service_file] = argument
    end
    opts.on('--pci_dss', 'update service keys') do |argument|
        service_settings[:pci_dss] = true
    end
    opts.on('--debug', "don't create backup machines") do |_argument|
        service_settings[:debug] = true
    end
    opts.on('--ami', "use this as an ami base machine") do |_argument|
        service_settings[:ami] = true
    end
    opts.on('--wait_to_register', "time to wait before trying to register in ALB") do |argument|
        service_settings[:wait_to_register] = argument.to_i || 1
    end
end.parse!

# check the settings
raise OptionParser::MissingArgument if service_settings[:environment].nil? || service_settings[:environment] == ''
raise OptionParser::MissingArgument if service_settings[:build_number].nil? || service_settings[:build_number] == ''
raise OptionParser::MissingArgument if service_settings[:service_file].nil? || service_settings[:service_file] == ''
machine=nil
overrider=HashOverrider.new
service_settings[:servers_count]=1 if service_settings[:debug]
begin
  machine=YAML.load_file(service_settings[:service_file])
  overrider.override_hash!(machine,service_settings[:environment])
rescue => err
  machine=nil
  puts err
end
exit 1 if machine==nil
service_settings.merge!(machine)
if service_settings[:servers_count].nil? || service_settings[:servers_count] == 0
  if service_settings['machine'] && service_settings['machine']['servers_count']
    service_settings[:servers_count] = service_settings['machine']['servers_count']
  end
end
if service_settings[:servers_count].nil? || service_settings[:servers_count] == 0
    service_settings[:servers_count] = 1
end
if service_settings["deployment"]["service_type"] == 'http' && (service_settings["deployment"]["path_name"].nil? || service_settings["deployment"]["path_name"] == '')
    throw 'HTTP service must have a path.'
end
puts "\r\n\r\nservice file loaded"
puts "\r\n**** server will not be pushed! *****\r\n\r\n" if service_settings[:dont_push_to_lb]

sc = ServerCreator.new aws_setup_data
sc.notifire = Notifire.new
sc.notifire.use_time_stamp = true
force_create=service_settings['machine']['force_create'] if !force_create
force_create=false if force_create.nil?
if service_settings[:ami]
  service_settings[:dont_push_to_lb]=true
end
if (force_create||service_settings[:ami]) == true
  Helpers.log "force creating servers"
    sc.create_servers_from_parameters(service_settings)
else
    sc.create_or_update_server(service_settings)
end
