#!/usr/bin/ruby
require 'json'
require_relative 'betterez/VaultDriver'
require_relative 'betterez/AwsInstance'
require_relative 'betterez/Helpers'
require_relative 'betterez/OssecManager'

environments = ["staging","sandbox","production"]
environments.each do |environment|
  Helpers.log "cleaning #{environment}..."
  manager=OssecManager.new environment
  agents_data,code=manager.list_all_agents
  bad_items=[]
  all_items={}
  all_instances={}
  agents_data["items"].each do |item_data|
    bad_items<<item_data["id"] if item_data["status"]!="Active"
    all_items[item_data["ip"]]=item_data
  end
  instances=AwsInstance.get_instances_with_filters([{ name: 'tag:Environment', values: [environment] }],Helpers.load_json_data_to_hash("settings/aws-data.json"))
  instances.each do |instance|
    all_instances[instance.get_tag_by_name('Name')]=instance
  end

  index=1
  all_items.each do |item|
    if !all_instances.has_key?(item[1]["name"])
      next if item[1]["id"]=="000"
      puts "#{index}. remove #{item[1]["id"]}, ip #{item[1]["ip"]}  name #{item[1]["name"]}"
      index+=1
      manager.remove_agent_by_id(item[1]["id"])
    end
  end
end
