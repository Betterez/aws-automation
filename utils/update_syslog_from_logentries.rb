#!/usr/bin/ruby
require_relative '../betterez/VaultDriver'
require_relative '../betterez/Helpers'
require_relative '../betterez/AwsInstance'
require_relative '../betterez/Syslogger'

service ="btrz-worker-exports"
service ="betterez-app"
#environment = "sandbox"
#environment = "staging"
environment = "production"
settings_file='./settings/secrets.json'


puts "for environment #{environment}"
driver = VaultDriver.from_secrets_file environment, settings_file
aws_settings = Helpers.load_json_data_to_hash('settings/aws-data.json')
active_servers=Syslogger.get_all_repositories_servers_per_environment(environment,aws_settings)
logger=Syslogger.new(driver)
active_servers.each do |instance|
  puts "#{instance.get_tag_by_name("Name")} - #{logger.check_record_exists(instance)}"
  eligible,err=logger.check_service_eligibility(instance.get_tag_by_name("Repository"))
  if err
    puts "#{err} checking server #{instance.get_tag_by_name("Name")}"
    next
  end
  if !eligible
    puts "not eligible for syslog, check vault."
    next
  end
  if !logger.check_record_exists(instance)
    puts "adding missing record"
    puts logger.add_record_to_rsyslog(instance)
  end
end
puts "================================================\n"
