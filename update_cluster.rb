#!/usr/bin/ruby
require_relative('betterez/Ecs')
require_relative('betterez/NginxConfigurator')
require_relative('betterez/TaskAdapter')
require_relative('betterez/ConfigurationData')
clusterName=ARGV[0]

Helpers.log("updating configurations in cluster #{clusterName}.")

ecs=Ecs.new()
conf=NginxConfigurator.new(nil)
tasks=ecs.loadAllTasksPerCluster(clusterName)
confData=ConfigurationData.new(tasks,clusterName,ConfigurationData::ECS)
puts  conf.uploadNewConfigurations(confData.getConfigurationData())

Helpers.log "Done."
