require 'aws-sdk'
require_relative('BaseLoader')
require_relative('Helpers')

class Ecs < BaseLoader
  attr_accessor(:pending_trials,:waiting_time)
  def initialize
    super
    @ecs=getEcsObject()
    @ec2=getEC2Client()
    @pending_trials=25
    @waiting_time=3
  end

  def getEcsObject
    creds=Helpers.create_aws_authentication_token()
    Aws.config[:ssl_ca_bundle] ="cacert.pem"
    ecs = Aws::ECS::Client.new(
    region: @default_region,
    credentials: creds
    )
  end

  def getInterface
    @ecs
  end

  def getEC2Client
    creds=Helpers.create_aws_authentication_token()
    Aws.config[:ssl_ca_bundle] ="cacert.pem"
    Aws::EC2::Client.new(
    region: @default_region,
    credentials: creds
    )

  end

  def self.listPorts(tasks)
    ports=[]
    tasks.each do |task|
      ports.push(task[:host_port])
    end
    return ports
  end

  def getAvailablePort(clusterName)
    tasks=loadAllTasksPerCluster(clusterName)
    ports=Ecs.listPorts(tasks).sort!()
    (5000..50000).each do |port|
      if !ports.include?(port)
        return port
      end
    end
  end

  def listClusters
    instancesNumber=0
    clusters=[]
    response=@ecs.list_clusters(max_results: 10)
      #  response.cluster_arns.push("default")
    response.cluster_arns.each do |cluster|
      current_cluster={cluster_arn: cluster, instances: []}
      instance_response=@ecs.list_container_instances(cluster: cluster)
      instance_response[:container_instance_arns].each do |instance_data|
        current_cluster[:instances].push(instance_data)
      end
      clusters.push(current_cluster)
    end
    return clusters
  end

  def getTaskNameRegex
    taskNameRex=Regexp.new('[\w\:-]+\/([\w\d\_-]+)')
  end
  # loads description for listed tasks.
  # * +tasksArns+ - array of tasks arn (running ones)
  # * +clusterName+ - String - the cluster name in which to run
  def loadTasksDescriptions(tasksArns, clusterName)
    tasks=[]
    currentServiceName=nil
    taskNameRex=getTaskNameRegex()
    # doesn't return all tasks here. possible amazon issue
    tasks_description=@ecs.describe_tasks(cluster: clusterName, tasks: tasksArns)
    tasks_description.tasks.each do |description|
      if description.last_status=="PENDING" then
        raise "pending task!"
      end
      response=@ecs.describe_task_definition(task_definition: description[:task_definition_arn])
      response[:task_definition][:container_definitions][0][:environment].each do |variable|
        if  variable[:name] == "SERVICE_NAME" then
          currentServiceName=variable[:value]
        end
      end
      description.containers.each do |container|
        container.network_bindings.each do |network|
          tasks.push({status: description.last_status,
            taskArn: description.task_arn,
            container_port: network.container_port,
            host_port: network.host_port,
            taskDescriptionArn: description.task_definition_arn,
            taskName: taskNameRex.match(description.task_definition_arn)[1],
            containerArn: description.container_instance_arn,
            serviceName: currentServiceName
            })
          end
        end
      end
      return tasks
    end

    def loadTasksArns(clusterName)
      tasksArns=[]
      response=@ecs.list_tasks(
      cluster: clusterName,
      max_results: 100
      )
      response.task_arns.each do |task|
        tasksArns.push(task)
      end
      return tasksArns
    end

    def loadAllTasksPerCluster(cluster)
      tasksArns=loadTasksArns(cluster)
      tasks=[]
      if tasksArns.length==0 then
        return tasks
      end

      pending =true
      trials=@pending_trials
      while pending ==true and trials>=0
        begin
          pending =false
          tasks=loadTasksDescriptions(tasksArns, cluster)
        rescue Exception => msg
          if msg!="pending task!" then
            raise msg
          end
          pending =true
          sleep(@waiting_time)
          trials-=1
        end
      end
      containersArn=[]
      containersInfo=[]
      if(tasks.length==0)
        return tasks
      end
      tasks.each do |task|
        if (!containersArn.include? task[:containerArn]) then
          containersArn.push(task[:containerArn])
          containersInfo.push({taskArn: task[:taskArn], containerArn: task[:containerArn]})
        end
      end
      #update that with the container arn above.
      response=@ecs.describe_container_instances(cluster: cluster,
      container_instances: containersArn)
      response.container_instances.each_with_index do |containerData, index|
          containersInfo[index]["ec2_instance_id"]=containerData.ec2_instance_id
      end
      instancesId=[]
      containersInfo.each do |container|
        instancesId.push(container["ec2_instance_id"])
      end
      response=@ec2.describe_instances(
      dry_run: false,
      instance_ids: instancesId
      )
      index=0
      response.reservations.each do |record|
        record.instances.each do |instance|
          containersInfo[index][:instance_private_ip]=instance.private_ip_address
          containersInfo[index][:instance_public_ip]=instance.public_ip_address
          index+=1
        end
      end
      containersTable={}
      containersInfo.each do |container|
        containersTable[container[:containerArn]]=container
      end
      tasks.each do |task|
        if containersTable.has_key?(task[:containerArn]) then
          task[:instance_private_ip]=containersTable[task[:containerArn]][:instance_private_ip]
          task[:instance_public_ip]=containersTable[task[:containerArn]][:instance_public_ip]
        end
      end
      return tasks
    end

    # waits until a service is registered.
    def waitForService(clusterName,serviceName)
      waiting=true
      result=true
      peek_pending_count=0
      while waiting
        response=@ecs.list_services(cluster: clusterName, max_results: 100)
        response.service_arns.each  do |service_arn|
          match=getTaskNameRegex().match(service_arn)
          if(match and match[1]==serviceName)then
            service_info=@ecs.describe_services({cluster: clusterName, services: [serviceName]})
            if service_info.services[0].desired_count == service_info.services[0].running_count then
              waiting=false
              break
            end
          end
        end
        if waiting then
          sleep(@waiting_time)
        end
      end
      return result
    end

    def runTask (task, clusterName)
      task_definition_arn=""
      response=@ecs.register_task_definition(task)
      task_definition_arn=response[:task_definition][:task_definition_arn]
      allTasks=loadTasksArns(clusterName)
      trg=getTaskNameRegex()
      deregisterTasks=[]
      allTasks.each do |taskArn|
        nameMatch=trg.match(taskArn)
        if nameMatch and nameMatch[1] == task[:name]
          deregisterTasks.push(taskArn)
        end
      end

      @ecs.run_task(cluster: clusterName, task_definition: task_definition_arn)
    end

    def checkServiceExists (serviceName,clusterName)
      results={has_service: false,service_name: serviceName,available_name: serviceName}
      alternateServiceName=serviceName+"_alt"
      serviceNames=[serviceName,alternateServiceName]
      response=@ecs.list_services( cluster: clusterName,max_results: 10)
      response.service_arns.each do |service|
        serviceNames.each do |service_name|
          mc=getTaskNameRegex().match(service)
          if mc then
            if service_name == mc[1] then
              results[:service_name]=service_name
              if service_name == serviceNames[0] then
                results[:available_name]=serviceNames[1]
              else
                results[:available_name]=serviceNames[0]
              end
              results[:has_service]=true;
              return results
            end
          end
        end
      end
      return results
    end

    # create a service or update one if exists.
    # task is to be supplied if a new service is to be created.
    # task is created using the TaskAdapter[TaskAdapter.html] class.
    def createOrUpdateService (clusterName,task)
      task_definition_arn=nil
      serviceName=task.getServiceName
      service_results=checkServiceExists(serviceName,clusterName)
      task.host_port=getAvailablePort(clusterName)
      response=@ecs.register_task_definition(task.generateTaskData)
      task_definition_arn=response[:task_definition][:task_definition_arn]
      if service_results[:has_service] then
        serviceName=service_results[:available_name]
      end
      response=@ecs.create_service(cluster: clusterName,
      service_name: serviceName,
      task_definition: task_definition_arn,
      desired_count: task.getInstances())
      service_results[:service_arn]= response[:service][:service_arn]
      return service_results
    end

    def getTasksDefinitionForService(service_name,cluster_name)
      response=@ecs.describe_services(cluster: cluster_name, services: [service_name])
      if response.services.length == 0 then
        return nil
      end
      response.services[0].task_definition
    end

    def removeService (clusterName,serviceName)
      if !checkServiceExists(serviceName,clusterName)[:has_service] then
        return false
      end
      #response=@ecs.describe_services(cluster: clusterName,services: [serviceName])
      @ecs.update_service(cluster: clusterName, service: serviceName, desired_count: 0)
      @ecs.delete_service(cluster: clusterName, service: serviceName)
      return true
    end
    ### ecs ends
  end
