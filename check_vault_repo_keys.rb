#!/usr/bin/ruby
require_relative 'betterez/VaultDriver'
require_relative 'betterez/Helpers'
require_relative 'betterez/ELBClient'
require 'mongo'
require 'aws-sdk'
settings=Helpers.load_json_data_to_hash("settings/aws-data.json")
if ARGV.length==0
  puts "please select an environment"
  exit 1
end
location=ARGV[0].to_sym
if !settings.has_key? location
  puts "no values for #{location}"
  exit 1
end
if !settings[location].has_key? :vault
  puts "no vault value"
  exit 1
end
db_server_parameters=Helpers.get_db_server_address_for_environment (location)
throw "Can't get parameters for #{location}" if db_server_parameters.nil?
puts db_server_parameters
Mongo::Logger.logger.level = Logger::FATAL
vault_settings=settings[location][:vault]
driver=VaultDriver.new(vault_settings[:address],vault_settings[:port],vault_settings[:token])
driver.get_vault_status
if !driver.online
  puts "not online"
  exit 1
end
if driver.locked
  puts "driver locked "
  exit 1
end
if !driver.authorized
  puts  "bad token"
  exit 1
end
all_repos_names,code=driver.list_all_registered_repos
throw "vault error" if (code>399 || code==0 ||code==nil)
throw "bad list, #{all_repos_names.class}" if (all_repos_names.class !=Hash )
throw "empty list" if (all_repos_names==nil || all_repos_names=="")
aws_client_key="",aws_client_secret=""
mongo_user="",mongo_password=""
all_repos_names["repos"].keys.each do |current_repo|
  puts "Checking #{current_repo}"
  repo_data,code=driver.get_json("secret/#{current_repo}")
  if (code>399||repo_data==nil||repo_data=="")
    puts "didn't find this repo #{current_repo}"
    next
  end
  if (repo_data.has_key?("aws_service_key")||repo_data.has_key?("AWS_SERVICE_KEY"))
    puts "  aws entry was found, testing..."
    if repo_data.has_key?("AWS_SERVICE_KEY")
      aws_client_key=repo_data["AWS_SERVICE_KEY"]
      aws_client_secret=repo_data["AWS_SERVICE_SECRET"]
    else
        aws_client_key=repo_data["aws_service_key"]
        aws_client_secret=repo_data["aws_service_secret"]
    end
    aws_creds=Aws::Credentials.new(aws_client_key,aws_client_secret)
    sts_client = Aws::STS::Client.new(region: 'us-east-1',credentials: aws_creds)
    begin
      resp = sts_client.get_caller_identity({})
      puts  "  1.Account confirmed!\n  2.arn #{resp.arn}"
    rescue
      puts "#{current_repo} has a key, but doesn't seem to have valid aws entry"
    end
  else
    puts "  repo doesn't have aws access."
  end
  if ( repo_data.has_key?("mongo_db_username") )
    if  (db_server_parameters[:mongo_server]!=nil)
      Helpers.log "mongo info found, testing insertion on #{db_server_parameters[:mongo_server]},
       #{db_server_parameters[:database_name]},#{db_server_parameters[:replica_set_name]}."
      mongo_user=repo_data["mongo_db_username"]
      mongo_password=repo_data["mongo_db_password"]
      mongo_client=Mongo::Client.new([db_server_parameters[:mongo_server]],database: db_server_parameters[:database_name],user: mongo_user,
        password: mongo_password, replica_set: db_server_parameters[:replica_set_name],:connect => :direct)
      versions=mongo_client[:versions]
      document = { name: current_repo, environment: settings[:location].to_s }
      result=versions.insert_one(document)
      if result.n >0
        Helpers.log "  mongo access granted"
      else
        Helpers.log "  could not create a document"
      end
    else
      puts "  no mongo data for this environment, but there is a key"
    end
  else
    puts "  no mongo access data"
  end
  puts  "\n\n\n"
end
Helpers.log "done"
