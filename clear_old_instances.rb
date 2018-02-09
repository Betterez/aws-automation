#!/usr/bin/ruby
require_relative  "betterez/Helpers"
require_relative  "betterez/InstancesCleaner"
require_relative  "betterez/Notifire"
require 'optparse'
settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
cleaning_options={view_only: false}
OptionParser.new do |opts|
  opts.banner="usage #{__FILE__} [options]"
  opts.on("--environment ENVIRONMENT","environment type - staging,sandbox,production") do |argument|
    cleaning_options[:environment]=argument
  end
  opts.on("--build_delta BUILD_DELTA","back versions to keep after the last build") do |argument|
    cleaning_options[:build_delta]=argument.to_i
  end
  opts.on("--type TYPE","type to clean - app, api or worker") do |argument|
    cleaning_options[:type]=argument
  end
  opts.on("--view_only","view list, don't do anything") do
    cleaning_options[:view_only]=true
  end
end.parse!

raise OptionParser::MissingArgument if (  (cleaning_options[:environment] == nil )||( cleaning_options[:environment] == "" ) )
raise OptionParser::MissingArgument if (  (cleaning_options[:build_delta] == nil )||( cleaning_options[:build_delta] == "" ) )
raise OptionParser::MissingArgument if (  (cleaning_options[:type] == nil )||( cleaning_options[:type] == "" ) )

cleaner=InstancesCleaner.new(settings)
cleaner.notifire=Notifire.new
cleaner.clean(cleaning_options)
Helpers.log "Done"
