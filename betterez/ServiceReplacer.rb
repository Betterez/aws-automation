require_relative "Ecs"
require_relative("NginxConfigurator")
require_relative("ConfigurationData")
class ServiceReplacer
  # => time to wait between setting the old service to 0 weight till termination
  attr_accessor(:wait_period)
  attr_accessor(:service_name)
  attr_accessor(:cluster_name)
  attr_accessor(:postfix_name)
  attr_accessor(:notifire)
  def initialize(service_name,cluster_name)
    @wait_period=60
    @postfix_name="_alter"
    @cluster_name,@service_name=cluster_name,service_name

  end
  def updateService(task_adapter)
    if @service_name == nil or @cluster_name == nil then
      raise "Can't update service without a service name or cluster name"
    end
    ecs=Ecs.new
    tasks_list=[]
    send_notification("checking service")
    checkResults=ecs.checkServiceExists(@service_name,@cluster_name)
    if(checkResults[:has_service]==true) then
      send_notification("service exists")
        tasks_list=ecs.getTasksDefinitionForService(@service_name,@cluster_name)
    end
    send_notification("creating service")
    service_results=ecs.createOrUpdateService(@cluster_name,task_adapter)
    send_notification("waiting for service")
    service_ok=ecs.waitForService(@cluster_name,service_results[:service_name])
    if service_ok==false then
      exit(1)
    end
    send_notification("service created ok, loading all tasks")
    all_tasks=ecs.loadAllTasksPerCluster(@cluster_name)
    conf=ConfigurationData.new(all_tasks,@cluster_name)
    conf.filters=tasks_list
    nginx=NginxConfigurator.new(nil)
    send_notification("uploading configuration to nginx server")
    nginx.uploadNewConfigurations(conf.getConfigurationData)
    if checkResults[:has_service]==true then
      send_notification "removeing old server:1 waiting 1 minute"
      sleep @wait_period
      send_notification "removeing old server:removing"
      ecs.removeService(@cluster_name,checkResults[:service_name])
      send_notification "reloading tasks"
      all_tasks=ecs.loadAllTasksPerCluster(@cluster_name)
      conf=ConfigurationData.new(all_tasks,@cluster_name)
      send_notification "updating nginx"
      nginx.uploadNewConfigurations(conf.getConfigurationData)
    end
  end
  def send_notification(message)
    if @notifire then
      notifire.notify(0,message)
    end
  end
end
