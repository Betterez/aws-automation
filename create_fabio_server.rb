#!/usr/bin/ruby
require_relative 'betterez/VaultDriver'
require_relative 'betterez/Helpers'
require_relative 'betterez/Transaction'
require_relative 'betterez/ELBClient'
require_relative 'betterez/AwsInstance'
require 'net/ssh'
require 'net/scp'
require 'thread'
require 'optparse'

settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
service_settings = { servers_count: 1, release_mode: 'yes' }
OptionParser.new do |opts|
    opts.banner = "usage: #{__FILE__} [options]"
    opts.on('--env ENVIRONMENT', 'production,staging or sandbox') do |argument|
        service_settings[:environment] = argument
    end
    opts.on('--build_number BUILD_NUMBER', 'external build number') do |argument|
        service_settings[:build_number] = argument
    end
    opts.on('--servers_count COUNT', 'number of servers to create') do |argument|
        service_settings[:servers_count] = argument.to_i
    end
    opts.on('--release_mode RELEASE', 'release mode yes or no') do |argument|
        service_settings[:release_mode] = argument
    end
end.parse!
raise OptionParser::MissingArgument if service_settings[:environment].nil? || service_settings[:environment] == ''
raise OptionParser::MissingArgument if service_settings[:build_number].nil? || service_settings[:build_number] == ''

Helpers.log('starting')
# elb=ELBClient.new(settings,:staging)
Helpers.log('loading elbs')
leader_elbs = ELBClient.filter_elb_with_tags('Elb-Type' => 'leader', 'Environment' => service_settings[:environment], 'Release' => service_settings[:release_mode])
if !leader_elbs.empty?
    Helpers.log "Found leader elbs: #{leader_elbs}"
else
    Helpers.log 'No Leaders were found.'
    exit 1
end
inner_elbs = []
if !service_settings.key?(:release_mode) || service_settings[:release_mode].nil?
    service_settings[:release_mode] = 'yes'
    service_settings[:release_mode] = 'no' if service_settings[:environment] == 'production'
end

app_elb_names = ELBClient.filter_elb_with_tags('Elb-Type' => 'app', 'Environment' => service_settings[:environment], 'Release' => service_settings[:release_mode])
if !app_elb_names.empty?
    Helpers.log "inner elb found: #{app_elb_names}"
else
    Helpers.log 'No ebls found. exiting.'
    exit 1
end
client = Helpers.CreateELB
resp = client.describe_load_balancers(load_balancer_names: app_elb_names,
                                      page_size: 10)
Helpers.log('loaded. loading tags, building routes')
tags_resp = client.describe_tags(load_balancer_names: app_elb_names)
resp.load_balancer_descriptions.each do |elb_data|
    elb_conf = { dns: elb_data.dns_name, elb_name: elb_data.load_balancer_name, app_name: 'app' }
    tags_resp.tag_descriptions.each do |tag_info|
        next if tag_info.load_balancer_name != elb_data.load_balancer_name
        tag_info.tags.each do |tag|
            next unless tag.key == 'Path-Name'
            if tag.value[0] != '/'
                if tag.value == 'cart'
                    elb_conf2 = elb_conf.clone
                    elb_conf2[:app_name] = 'be-cart'
                    elb_conf2[:path] = '/' + 'be-cart'
                    inner_elbs.push elb_conf2
                end
                elb_conf[:app_name] = tag.value
                elb_conf[:path] = '/' + tag.value
            else
                elb_conf[:path] = tag.value
                elb_conf[:app_name] = 'betterez-app'
            end
        end
    end
    inner_elbs.push elb_conf
end
routes_data = ''
inner_elbs.each do |elb_conf|
    routes_data += "route add #{elb_conf[:app_name]} #{elb_conf[:path]} http://#{elb_conf[:dns]}\r\n"
end
puts "routes_data = #{routes_data}"
Helpers.log('done, creating server(s)')
runners = []
servers = []
servers_data = []
limiter = Random.new
(1..service_settings[:servers_count]).each do
    sleep ( 0.1+limiter.rand(2000)/100 )
    runners << Thread.new do
        setup_data = Helpers.create_setup_data(service_settings[:environment], 'fabio')
        setup_data[:build_number] = service_settings[:build_number]
        server = AwsInstance.create_aws_instance(setup_data, settings)
        output = ''
        Helpers.log 'waiting for the server to start...'
        sleep 10
        Helpers.log 'checking server response...'
        while nil == output.index('200')
            sleep 10
            output = server.run_ssh_command 'curl -i localhost:8080'
            puts "done with #{output}"
        end
        Helpers.log 'redirector checked'
        server.upload_data_to_file routes_data, 'routes.tbl'
        server.run_ssh_command 'sudo service fabio restart'
        Helpers.log 'waiting for the http server to start...'
        sleep 10
        output = ''
        Helpers.log 'Checking app route...'
        while nil == output.index('200')
            output = server.run_ssh_command 'curl -i localhost:5000'
            sleep 10
        end
        puts "done with #{output}"
        servers << server
        servers_data << { instance_id: server.aws_instance_data.instance_id }
    end
end
runners.each(&:join)
Helpers.log('done, installing in elbs...')
leader_elbs.each do |leader_elb|
    puts "updating #{leader_elb}"
    ELBClient.update_elb_instances leader_elb, servers_data
end
Helpers.log 'Done.'
