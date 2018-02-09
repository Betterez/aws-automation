require_relative 'Helpers'
class Switcher
  attr_accessor :notifire
  def initialize(source, targets)
    @sourceELBName = source
    @targetELBNames = targets
  end

  def createClient
    Aws.config[:ssl_ca_bundle] = 'cacert.pem'
    elasticloadbalancing = Aws::ElasticLoadBalancing::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
  end

  def outputMessage(message)
    @notifire.notify(0, message) unless @notifire.nil?
  end

  def listAll
    resp = createClient.describe_load_balancers
    elbNames = []
    resp.load_balancer_descriptions.each do |elb|
      elbNames.push(elb.load_balancer_name)
    end
    elbNames
  end

  def checkElbInstances
    list = listAll
    targetInstances = {}
    unless list.include?@sourceELBName
      return false, "source elb '#{@sourceELBName}' doesn't exist"
    end
    @targetELBNames.each do |targetName|
      unless list.include?targetName
        return false, "target elb #{targetName} doesn't exist"
      end
    end
    client = createClient
    sourceInstances = []
    resp = client.describe_load_balancers(load_balancer_names: [@sourceELBName])
    resp.load_balancer_descriptions.each do |description|
      description.instances.each do |instance|
        sourceInstances.push(instance.instance_id)
      end
    end

    @targetELBNames.each do |elb_name|
      targetInstances[elb_name] = []
      resp = client.describe_load_balancers(load_balancer_names: [elb_name])
      resp.load_balancer_descriptions.each do |description|
        description.instances.each do |instance|
          if sourceInstances.include?instance.instance_id
            return false, 'target instance already exists in target elb'
          end
        end
      end
    end
    true
  end

  def switch
    result, reason = checkElbInstances
    return false, reason unless result
    error = nil
    targetInstances = {}
    client = createClient
    sourceInstances = []
    outputMessage "loading instances from #{@sourceELBName}"
    resp = client.describe_load_balancers(load_balancer_names: [@sourceELBName])
    resp.load_balancer_descriptions.each do |description|
      description.instances.each do |instance|
        sourceInstances.push(instance.instance_id)
      end
    end
    outputMessage 'Reading current instances in switch elb...'
    @targetELBNames.each do |elb_name|
      targetInstances[elb_name] = []
      resp = client.describe_load_balancers(load_balancer_names: [elb_name])
      resp.load_balancer_descriptions.each do |description|
        description.instances.each do |instance|
          if sourceInstances.include?instance.instance_id
            outputMessage("instance is #{instance.instance_id} already in target. exiting.")
            error = "instance #{instance.instance_id} exist in target"
            break
          end
          targetInstances[elb_name].push(instance_id: instance.instance_id)
        end
      end
    end
    return false, error unless error.nil?
    # register betterlive instances
    outputMessage "Registering #{@sourceELBName} instances in target elbs..."
    instancesToPush = []
    sourceInstances.each do |instance|
      instancesToPush.push(instance_id: instance)
    end
    @targetELBNames.each do |elb_name|
      resp = client.register_instances_with_load_balancer(load_balancer_name: elb_name, instances: instancesToPush)
    end

    hops = 0
    working = false
    workingCount = 0
    time_to_sleep = 20
    while hops < 20
      outputMessage "Checking status (#{time_to_sleep})..."
      sleep(time_to_sleep)
      workingCount = 0
      @targetELBNames.each do |elb_name|
        outputMessage "checking instance for #{elb_name}:"
        resp = client.describe_instance_health(load_balancer_name: elb_name, instances: instancesToPush)
        resp.instance_states.each do |state|
          if state.state != 'InService'
            outputMessage "failed #{elb_name} (#{state.state}):"
            break
          else
            outputMessage "ok #{elb_name}: #{state.instance_id}"
            workingCount += 1
          end
        end
      end
      hops += 1
      next unless workingCount == instancesToPush.length * @targetELBNames.length
      outputMessage("everything working, #{workingCount} instances updated")
      working = true
      break
    end
    @targetELBNames.each do |elb_name|
      if targetInstances[elb_name].length > 0
        outputMessage "deregistering servers from #{elb_name}..."
        client.deregister_instances_from_load_balancer(load_balancer_name: elb_name, instances: targetInstances[elb_name])
      else
        outputMessage "#{elb_name} has no instances to de-register"
      end
    end
    if working
      outputMessage 'Switch done.'
      return true, nil
    else
      outputMessage 'error switching instances.'
      return false, 'error'
    end
  end
end
