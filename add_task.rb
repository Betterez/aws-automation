require_relative('betterez/Ecs')
require_relative('betterez/NginxConfigurator')
require_relative('betterez/TaskAdapter')
#adds an ecs task
def addTaskToCluster(clusterName,taskFile)
  if !File.exist?(taskFile)then
    raise "can't find definition file #{taskFile}!"
  end
  lb_config=Helpers.loadJSONData("settings/settings.json")
  if  !lb_config.has_key?(clusterName) then
    raise "can't find nginx lb data for the cluster #{clusterName}."
  end
  ecs=Ecs.new()
  Helpers.log "checking for a port"
  port=ecs.getAvailablePort(clusterName)
  Helpers.log "port #{port} was selected."
  task=TaskAdapter.new(taskFile)
  task.environment=clusterName
  task.host_port=port
  Helpers.log "registering task.."
  ecs.runTask(task.generateTaskData(),clusterName)
  Helpers.log "run task. connecting to nginx"
  config=NginxConfigurator.new(server_name: "#{clusterName} balancer")
  runningTasks=ecs.loadAllTasksPerCluster(clusterName)
  info={:tasks=>runningTasks, :lb=>lb_config[clusterName]}
  config.uploadNewConfigurations(info)
  Helpers.log "Done."
end
if ARGV.length <2 then
  puts "bad arguments. usage is environment, task definition file"
  return
end
addTaskToCluster(ARGV[0],ARGV[1])
