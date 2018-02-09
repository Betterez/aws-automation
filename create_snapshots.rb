#!/usr/bin/ruby
require_relative 'betterez/VaultDriver'
require_relative 'betterez/AwsInstance'
require_relative 'betterez/Helpers'

filters = [
  { name: 'tag:Service-Type', values: %w[jenkins vault] }
]

client = Helpers.create_aws_ec2_client
settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
instances = AwsInstance.get_instances_with_filters(filters, settings)
instances.each do |instance|
  description = "#{Helpers.create_time_date_string} stamp for #{instance.get_tag_by_name('Name')} on #{instance.get_tag_by_name('Environment')}"
  volume_id = instance.aws_instance_data.block_device_mappings[0].ebs.volume_id
  Helpers.log "snapshotting #{description}"
  resp = client.create_snapshot(description: description,
                                volume_id: volume_id)
  # tag here with the id
  # resp.snapshot_id #=> String
  Helpers.log "wating 10 sec for tagging"
  sleep(10)
  client.create_tags(dry_run: false,
                     resources: [resp.snapshot_id], # required
                     tags: [ # required
                       {
                         key: 'Name',
                         value: "#{instance.get_tag_by_name('Name')}_#{instance.get_tag_by_name('Environment')}_#{Helpers.create_time_date_string}"
                       }
                     ])
end
