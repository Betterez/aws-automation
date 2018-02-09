#!/usr/bin/ruby
require 'aws-sdk'
require 'optparse'
require_relative 'betterez/Helpers'

calling_parameters={}
OptionParser.new do |opts|
  opts.banner = "usage: #{__FILE__} [options]"
  opts.on('--sqs SQS_PATH', 'sqs url.') do |argument|
    calling_parameters[:sqs_url] = argument
  end
  opts.on('--message MESSAGE_STRING','the message string to pass to the queue') do |argument|
    calling_parameters[:message] = argument
  end
end.parse!
raise OptionParser::MissingArgument if calling_parameters[:sqs_url].nil? || calling_parameters[:sqs_url] == ''
raise OptionParser::MissingArgument if calling_parameters[:message].nil? || calling_parameters[:message] == ''


sqs_client = Aws::SQS::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
sqs_client.send_message({
  queue_url: calling_parameters[:sqs_url] , # required
  message_body: calling_parameters[:message], # required
  delay_seconds: 1,
  message_attributes: {
    "String" => {
      string_value: "All",
      data_type: "String", # required
    },
  },
  # message_deduplication_id: "String",
  # message_group_id: "String",
})

Helpers.log "done"
