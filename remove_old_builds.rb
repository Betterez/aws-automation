#!/usr/bin/ruby

require_relative 'betterez/ELBClient'
require_relative 'betterez/Helpers'
groups_to_check = ELBClient.filter_groups_with_tags('Elb-Type' => 'api',
                                                    'Environment' => 'sandbox')
aws_setup_data = Helpers.load_json_data_to_hash('settings/aws-data.json')
elb_client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
groups_to_check.each do |current_group|
  targets_description = elb_client.describe_target_health(target_group_arn: current_group[:target_group_arn]).target_health_descriptions
  next if targets_description.length < 2

  targets_description.each do |_target_description|
    next unless _target_description[:target_health][:state] == 'healthy'

    current_insatance = AwsInstance.get_instances_with_id(_target_description[:target][:id], aws_setup_data)
    puts "#{current_insatance.name} - #{current_insatance.build_number}"
  end
end
