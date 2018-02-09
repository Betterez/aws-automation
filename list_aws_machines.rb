#!/usr/bin/ruby
require_relative 'betterez/Helpers'
require_relative 'betterez/AwsInstance'
require_relative 'betterez/ELBClient'
require_relative 'betterez/ConnexTester'
require_relative 'betterez/AwsInstance'
require_relative 'utils/HashOverrider'
require 'yaml'
require 'aws-sdk'

# settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
Helpers.log 'starting'
ec2_client = Helpers.create_aws_ec2_client
resp = ec2_client.describe_instances(dry_run: false,
                                     max_results: 100)
results = {}

resp.reservations.each do |instances_data|
    instances_data.instances.each do |instance_data|
        instance_environment = nil
        instance_serving_type = nil
        instance_nginx_conf=nil

        instance_data.tags.each do |tag|
            instance_environment = tag.value if tag[:key] == 'Environment'
            instance_serving_type = tag.value if tag[:key] == 'Service-Type'
            instance_nginx_conf = tag.value if tag[:key] == 'Nginx-Configuration'
        end

        if instance_nginx_conf!=nil && instance_nginx_conf!='none'
          instance_serving_type=instance_nginx_conf
        else
          instance_serving_type = 'unknown' if instance_serving_type.nil?
        end
        instance_environment = 'unknown' if instance_environment.nil?

        if results.key?(instance_environment)
            results_env = results[instance_environment]
            if results_env.key?(instance_data.instance_type)
                results_env_typed = results_env[instance_data.instance_type]
                if results_env_typed.key?(instance_serving_type)
                    results_env_typed[instance_serving_type][:quantity] += 1
                else
                    results_env_typed[instance_serving_type] = { quantity: 1 }
                end
            else
                results_env[instance_data.instance_type] = { instance_serving_type => { quantity: 1 } }
            end
        else
            results[instance_environment] = { instance_data.instance_type => { instance_serving_type => { quantity: 1 } } }
        end
    end
end
#puts results
csv_file=File.open("output/servers.csv","w")
results.keys.each do |environemnt|
  csv_file.write("#{environemnt}\n")
  results[environemnt].keys.each do |server_type|
    csv_file.write("server type,btrz type,quantity,required\n")
    results[environemnt][server_type].each do |instance_data|
      btrz_conf=instance_data[0]
      csv_file.write("#{server_type},#{btrz_conf},#{instance_data[1][:quantity]}\n")
    end
  end
end
csv_file.close();
Helpers.log 'done'
