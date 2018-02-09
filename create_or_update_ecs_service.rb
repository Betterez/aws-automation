#!/usr/bin/ruby
require_relative('betterez/Ecs')
require_relative('betterez/NginxConfigurator')
require_relative('betterez/TaskAdapter')
require_relative('betterez/ServiceReplacer')
require_relative('betterez/ConfigurationData')
require_relative('betterez/Notifire')

ecs=Ecs.new()
rx=ecs.getTaskNameRegex()
#list services - check it doesn't exists
if ARGV.length()<2 then
  puts  "must use with [cluster name][task file]"
  return 1
end
Helpers.log("loading configuration")
cluster_name=ARGV[0]
task_file=ARGV[1]

task_adapter=TaskAdapter.new(task_file)
notifire=Notifire.new
Helpers.log("creating #{task_adapter.getServiceName()} service")
task_adapter.environment=cluster_name
Helpers.log("updating/creating service...")
replacer=ServiceReplacer.new(task_adapter.getServiceName,cluster_name)
replacer.notifire=notifire
replacer.updateService(task_adapter)
Helpers.log("Done.")
