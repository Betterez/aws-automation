#!/usr/bin/ruby
require_relative('../betterez/Ecs')
if ARGV.length()<1 then
  puts  "must use with [cluster name]"
  return 1
end
clusterName=ARGV[0]
Helpers.log("starting task")

ecs=Ecs.new()

def loadFromEcs(ecs,clusterName)
  puts "Loading tasks from ecs object"
  all_tasks=ecs.loadAllTasksPerCluster(clusterName)
  puts "#{all_tasks.length} tasks were loaded"
  all_tasks.each do |task|
    puts task
  end
end

def loadNatural(ecs,clusterName)
  puts "Loading directly from amazon"
  aws=ecs.getInterface
  arns=[]
  aws.list_tasks({cluster: clusterName}).each do |page|
    page.task_arns.each do |arn|
      # puts arn
      arns.push arn
    end
  end
  puts "Loading tasks for #{arns.length()} tasks:"
  tasks=aws.describe_tasks({cluster: clusterName, tasks: arns})
  tasks.tasks.each do |description|
    puts aws.describe_task_definition(task_definition: description[:task_definition_arn]).task_definition
  end
end
#loadNatural(ecs,clusterName)
loadFromEcs(ecs,clusterName)
Helpers.log("done")
