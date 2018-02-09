#!/usr/bin/ruby
require 'json'
require_relative 'betterez/VaultDriver'
require_relative 'betterez/AwsInstance'
require_relative 'betterez/Helpers'
require_relative 'betterez/BetterezAppTester'
require 'optparse'

aws_regions = ['us-west-2', 'us-east-1']
all_aws_regions_missing_params = {}
instance_types = []
reporter_settings={email: true}

OptionParser.new do |opts|
    opts.banner = 'report instance'
    opts.on('--email OPTION', 'yes or no') do |argument|
        reporter_settings[:email]=false if argument=="no"
    end
    opts.on('--rec RECIPIENTS', 'emails recipients to email to, separated by a commas') do |argument|
        reporter_settings[:recipients]=argument
    end
    opts.on('--from SENDER', 'email sender') do |argument|
        reporter_settings[:from]=argument
    end
end.parse!
if reporter_settings[:email]!=false
  fail OptionParser::MissingArgument if reporter_settings[:recipients].nil? || reporter_settings[:recipients] == ''
  fail OptionParser::MissingArgument if reporter_settings[:from].nil? || reporter_settings[:from] == ''
end

Aws.config[:ssl_ca_bundle] = 'cacert.pem'
ses_client = Aws::SES::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)

aws_regions.each do |current_region|
  running_instances_by_type = {}
  reservation_by_type = {}
  missing_instances = {}
  puts "\n\nregion #{current_region} - loading all instances data...\n"
  all_instances = AwsInstance.get_instances_with_filters(
    [{ name: 'instance-state-name', values: ['running'] }],
    Helpers.load_json_data_to_hash('settings/aws-data.json'),
    current_region
  )
  Helpers.log 'done'

  all_instances.each do |instance|
    next if instance.get_tag_by_name('Reservation') == 'no'
    if !running_instances_by_type.key?(instance.instance_type)
      running_instances_by_type[instance.instance_type] = [instance]
    else
      running_instances_by_type[instance.instance_type].push instance
    end
  end

  Helpers.log 'loading reserved instance'
  ec2_client = Helpers.create_aws_ec2_client(current_region)
  resp = ec2_client.describe_reserved_instances(filters: [
                                                  { name: 'state',
                                                    values: ['active'] }
                                                ])
  resp.reserved_instances.each do |reservation|
    reservation_by_type[reservation.instance_type] = 0 unless reservation_by_type.key?(reservation.instance_type)
    reservation_by_type[reservation.instance_type] = reservation_by_type[reservation.instance_type] + reservation.instance_count
  end
  instance_types.concat running_instances_by_type.keys
  instance_types.concat reservation_by_type.keys

  instance_types.each do |instance_type|
    if !running_instances_by_type[instance_type].nil? && !reservation_by_type[instance_type].nil?
      missing_instances[instance_type] = running_instances_by_type[instance_type].length - reservation_by_type[instance_type]
    elsif !running_instances_by_type[instance_type].nil? && reservation_by_type[instance_type].nil?
      missing_instances[instance_type] = running_instances_by_type[instance_type].length
    elsif running_instances_by_type[instance_type].nil? && !reservation_by_type[instance_type].nil?
      missing_instances[instance_type] = reservation_by_type[instance_type] * -1
    end
  end
  unless missing_instances.empty?
    all_aws_regions_missing_params[current_region] = missing_instances.clone
  end
end
puts "\n\n"
data_body = ''
total_remarks = 0
all_aws_regions_missing_params.keys.each do |current_region|
  data_body += "for region #{current_region}\n==========================\n"
  all_aws_regions_missing_params[current_region].keys.each do |instance_type|
    if all_aws_regions_missing_params[current_region][instance_type] > 0
      total_remarks += 1
      data_body += "#{all_aws_regions_missing_params[current_region][instance_type]} of #{instance_type} should be reserved\n"
    end
    if all_aws_regions_missing_params[current_region][instance_type] < 0
      total_remarks += 1
      data_body += "#{all_aws_regions_missing_params[current_region][instance_type] * -1} of #{instance_type} are reserved and not used.\n"
    end
  end
  data_body += "\n"
end

puts data_body
if all_aws_regions_missing_params.key?('us-east-1') &&
   !all_aws_regions_missing_params['us-east-1']['t2.medium'].nil? &&
   (all_aws_regions_missing_params['us-east-1']['t2.medium'] > 0 && all_aws_regions_missing_params['us-east-1']['t2.medium'] < 8)
  total_remarks -= 1
end

if (total_remarks > 0 && reporter_settings[:email])
  ses_client.send_email(destination: {
                          to_addresses: reporter_settings[:recipients].split(","),
                          cc_addresses: [],
                          bcc_addresses: []
                        },
                        message: {
                          body: {
                            text: {
                              charset: 'UTF-8',
                              data: data_body
                            }
                          },
                          subject: {
                            charset: 'UTF-8',
                            data: 'Instances need attention'
                          }
                        },
                        reply_to_addresses: [
                          reporter_settings[:from]
                        ],
                        return_path: reporter_settings[:from],
                        source: reporter_settings[:from])
end

Helpers.log 'done'
