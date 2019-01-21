#!/usr/bin/ruby
require_relative  'Helpers'
require_relative  'AwsInstance'
# create elb for betterez
class ELBClient
  def initialize(settings, environment)
    @settings = settings
    @environment = environment
    @ssl_certificate_arn = Helpers.get_cretificate_arn
    @prod_public_security = Helpers.get_production_security_groups_for_type('public')
    @prod_public_https = Helpers.get_production_security_groups_for_type('https')
    @prod_public_subnets = Helpers.get_public_prodcution_subnets
    @private_security = [settings[environment][:infraStructure][0][:securityGroup]]
    @private_subnets = []
    settings[environment][:infraStructure].each do |infra|
      @private_subnets.push(infra[:subnet])
    end
  end

  def create_listener
    {
      protocol: 'HTTP',
      instance_protocol: 'HTTP',
      load_balancer_port: 80,
      instance_port:  80
    }
  end

  # generates a configuration hash from a configuration data.
  # * +configuration_data+ - hash - the configuration data
  # * +environment+ - string - environemnt name
  def self.create_from_albs_configuration(configuration_data, environment)
    alb_client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    kept_data = { albs: [] }
    current_alb_index = 0
    configuration_data[:albs].each do |alb|
      alb[:domains].each do |domain|
        alb_name = "#{environment}-#{alb[:alb_type]}-#{domain[:name]}-alb"
        alb_configuration = {
          name: alb_name, # required
          subnets: configuration_data[:subnets],
          security_groups: configuration_data[:security_groups],
          scheme: configuration_data[:scheme],
          tags: [
            {
              key: 'Alb-Type', # required
              value: alb[:alb_type]
            },
            {
              key: 'Environment', # required
              value: environment
            },
            {
              key: 'Domain', # required
              value: domain[:name]
            }
          ]
        }
        resp = alb_client.create_load_balancer(alb_configuration)
        Helpers.log "Created alb #{alb_name}"
        kept_data[:albs] << { domain_name: domain[:name], alb_data: { alb_name: alb_name, alb_arn: resp[:load_balancers][0][:load_balancer_arn], services: [] } }
        default_alb_service_index = 0
        alb[:services].each_with_index do |the_service, service_index|
          default_alb_service_index = service_index if the_service[:default]
        end
        priority_index = 0
        alb[:services].each_with_index do |service, service_index|
          tg_healthcheck = service[:healthcheck] if service[:healthcheck]
          tg_healthcheck = "/#{service[:name]}/healthcheck" if service[:healthcheck].nil?
          tg_name = "#{environment}-#{service[:name]}-#{domain[:name]}-tg"
          tg_name = tg_name.slice(0, 31) if tg_name.length > 32
          tg_name = tg_name.slice(0, 30) if tg_name[tg_name.length - 1] == '-'

          service_path = service[:path] if service[:path]
          service_path = service[:name] if service[:path].nil?
          tg_conf = {
            name: tg_name,
            protocol: 'HTTP',
            port: 3000,
            vpc_id: configuration_data[:vpc_id], # required
            health_check_protocol: 'HTTP', # accepts HTTP, HTTPS
            health_check_port: '3000',
            health_check_path: tg_healthcheck,
            health_check_interval_seconds: 30,
            health_check_timeout_seconds: 10,
            healthy_threshold_count: 2,
            unhealthy_threshold_count: 2,
            matcher: {
              http_code: '200', # required
            }
          }
          Helpers.log "Created tg #{tg_name}"
          kept_data[:albs][current_alb_index][:alb_data][:services] << {
            tg_arn: alb_client.create_target_group(tg_conf).target_groups[0].target_group_arn,
            service_name: service[:name]
          }
          alb_client.add_tags(resource_arns: [
                                kept_data[:albs][current_alb_index][:alb_data][:services][service_index][:tg_arn]
                              ],
                              tags: [
                                {
                                  key: 'Elb-Type',
                                  value: alb[:alb_type]
                                },
                                {
                                  key: 'Environment',
                                  value: environment
                                },
                                {
                                  key: 'Release',
                                  value: 'yes'
                                },
                                {
                                  key: 'Version',
                                  value: '2'
                                },
                                {
                                  key: 'Path-Name',
                                  value: service_path
                                }
                              ])
          # default listener is https
          service[:listeners] = ['HTTPS'] unless service[:listeners]
          default_tg_arn = kept_data[:albs][current_alb_index][:alb_data][:services][default_alb_service_index][:tg_arn]
          certificate_arn = domain[:certificate_arn]
          listener_arn = nil
          service[:listener_paths] = ["/#{service[:name]}/*"] unless service[:listener_paths]
          Helpers.log "service: #{service[:name]}, domain: #{domain[:name]}, alb: #{kept_data[:albs][current_alb_index][:alb_data][:alb_name]}"
          service[:listeners].each do |listener|
            if listener == 'HTTPS'
              Helpers.log "creating listener #{listener} in HTTPS"
              resp = alb_client.create_listener(
                certificates: [
                  {
                    certificate_arn: certificate_arn
                  }
                ],
                default_actions: [
                  {
                    target_group_arn: default_tg_arn,
                    type: 'forward'
                  }
                ],
                load_balancer_arn: kept_data[:albs][current_alb_index][:alb_data][:alb_arn],
                port: 443,
                protocol: 'HTTPS',
                ssl_policy: 'ELBSecurityPolicy-2015-05'
              )
            elsif listener == 'HTTP'
              Helpers.log "creating listener #{listener} in HTTP"
              resp = alb_client.create_listener(
                default_actions: [
                  {
                    target_group_arn: default_tg_arn,
                    type: 'forward'
                  }
                ],
                load_balancer_arn: kept_data[:albs][current_alb_index][:alb_data][:alb_arn],
                port: 80,
                protocol: 'HTTP'
              )
              end
            listener_arn = resp.listeners[0].listener_arn
            service[:listener_paths].each do |service_listener_path|
              priority_index += 1
              next if service[:default]
              Helpers.log "Adding rule '#{service_listener_path}': service: #{service[:name]}, domain: #{domain[:name]}, alb: #{kept_data[:albs][current_alb_index][:alb_data][:alb_name]}, priority:#{priority_index}"
              alb_client.create_rule(listener_arn: listener_arn, # required
                                     conditions: [ # required
                                       {
                                         field: 'path-pattern',
                                         values: [service_listener_path]
                                       }
                                     ],
                                     priority: priority_index, # required
                                     actions: [ # required
                                       {
                                         type: 'forward', # required, accepts forward
                                         target_group_arn: kept_data[:albs][current_alb_index][:alb_data][:services][service_index][:tg_arn], # required
                                       }
                                     ])
            end
          end
        end
        current_alb_index += 1
      end
    end
  end

  def create_https_listener
    https_listener = create_listener
    https_listener[:load_balancer_port] = 443
    https_listener[:protocol] = 'HTTPS'
    https_listener[:ssl_certificate_id] = @ssl_certificate_arn
    https_listener[:instance_port] = 80
    https_listener
  end

  def create_elb_entry
    {
      load_balancer_name: '',
      listeners: [create_listener, create_https_listener]
    }
  end

  ## create an elb. dual set to create another listener on 5000.
  # * +dual+ - use 5000 as a listener
  def create_elb(params)
    elb = Helpers.CreateELB()
    if !params.key? entry:
      entry = create_elb_entry
    else
      entry = params[:entry]
    end
    entry[:load_balancer_name] = params[:elb_name]
    if params[:internal]
      entry[:subnets] = @private_subnets
      entry[:security_groups] = @private_security
      entry[:scheme] = 'internal'
    else
      entry[:subnets] = @prod_public_subnets
      entry[:security_groups] = @prod_public_https_security
    end
    if params[:instance_port]
      entry[:listeners][0][:instance_port] = params[:instance_port]
    end
    if params[:secure]
      if params[:instance_secure_port]
        entry[:listeners][1][:instance_port] = params[:instance_secure_port]
      end
    else
      entry[:listeners].delete_at(1)
    end
    elb_resp = elb.create_load_balancer(entry)
    health_check_target = if params.key? :health_check_target
                            params[:health_check_target]
                          else
                            'HTTP:80/healthcheck'
                          end
    health_check = elb.configure_health_check(load_balancer_name: params[:elb_name],
                                              health_check: {
                                                target: health_check_target,
                                                interval: 30,
                                                timeout: 10,
                                                unhealthy_threshold: 2,
                                                healthy_threshold: 2
                                              })
    { elb: elb_resp, health_check: health_check }
  end

  # returns an array of +sting+ names of elbs
  # * +tag_filters+ - a hash of tag to use in a name=>value settings
  def self.filter_elb_with_tags(tag_filters)
    client = Helpers.CreateELB
    resp = client.describe_load_balancers
    elbs = []
    resp.load_balancer_descriptions.each do |current_elb_data|
      resp2 = client.describe_tags(load_balancer_names: [current_elb_data.load_balancer_name])
      instance_match = 0
      resp2.tag_descriptions.each do |current_elb_tags_data|
        current_elb_tags_data.tags.each do |current_tag_data|
          if (tag_filters.keys.include? current_tag_data.key) && (tag_filters[current_tag_data.key] == current_tag_data.value)
            instance_match += 1
            end
          if instance_match == tag_filters.keys.length
            elbs.push current_elb_data.load_balancer_name
            break
          end
        end
      end
    end
    elbs
  end

  # returns an array of load balancer data names of elbs
  # * +tag_filters+ - a hash of tag to use in a name=>value settings
  def self.get_elb_data_with_tags(tag_filters)
    client = Helpers.CreateELB
    resp = client.describe_load_balancers
    elbs = []
    resp.load_balancer_descriptions.each do |current_elb_data|
      resp2 = client.describe_tags(load_balancer_names: [current_elb_data.load_balancer_name])
      instance_match = 0
      resp2.tag_descriptions.each do |current_elb_tags_data|
        current_elb_tags_data.tags.each do |current_tag_data|
          if (tag_filters.keys.include? current_tag_data.key) && (tag_filters[current_tag_data.key] == current_tag_data.value)
            instance_match += 1
            end
          if instance_match == tag_filters.keys.length
            elbs.push current_elb_data
            break
          end
        end
      end
    end
    elbs
  end

  # returns a filtered list of albs that has all the tags with the mentioned value
  # * +tag_filters+ - a hash of tag to use in a name=>value settings
  def self.filter_alb_with_tags(tag_filters)
    alb_client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    resp = alb_client.describe_load_balancers(page_size: 30)
    albs = []
    resp.load_balancers.each do |current_elb_data|
      resp2 = alb_client.describe_tags(resource_arns: [current_elb_data.load_balancer_arn])
      instance_match = 0
      resp2.tag_descriptions.each do |current_elb_tags_data|
        current_elb_tags_data.tags.each do |current_tag_data|
          if (tag_filters.keys.include? current_tag_data.key) && (tag_filters[current_tag_data.key] == current_tag_data.value)
            instance_match += 1
            end
          if instance_match == tag_filters.keys.length
            albs.push current_elb_data.load_balancer_name
            break
          end
        end
      end
    end
    albs
  end

  def self.sanitize_tg_arn(name)
    location = name.index('targetgroup')
    return nil if location.nil?
    name.slice(location, name.length)
  end

  def self.sanitize_alb_arn(name)
    separator = 'loadbalancer/'
    location = name.index(separator)
    return nil if location.nil?
    name.slice(location + separator.length, name.length)
  end

  # returns an array of instances id contains within the elbs mentioned
  # * +elb_names+ - an array of strings
  def self.list_all_instances_in_elbs(elb_names)
    throw 'bad elb names parameters' if elb_names.class != Array
    return [] if elb_names.empty?
    client = Helpers.CreateELB
    found_instances = []
    client.describe_load_balancers(load_balancer_names: elb_names).load_balancer_descriptions.each do |description|
      description.instances.each do |instance|
        unless found_instances.include? instance.instance_id
          found_instances.push(instance.instance_id)
          end
      end
    end
    found_instances
  end

  def self.list_all_instances_in_target_groups_with_tag_filters(tag_filters)
    client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)

    instances =[]
    target_groups = ELBClient.filter_groups_with_tags(tag_filters )
    if target_groups.empty?
      return instances
    else
      target_groups.each do |target_group|
        resp=client.describe_target_health({target_group_arn: target_group.target_group_arn})
        resp.target_health_descriptions.each do |target_desc|
          instances << target_desc.target.id if target_desc.target_health=="unused"  || target_desc.target_health="healthy"
        end
      end
    end
      return instances
  end

  # update existing elb - remove old instances and inserting new ones
  #
  # This will wait till the new ones are "InService", the function returns only when it's done
  # * +instance_ids_to_register+ - An array of instances_id to insert
  def self.update_elb_instances(elb_name, instance_ids_to_register)
    client = Helpers.CreateELB
    existing_instances = []
    instance_ids_array = []
    instance_ids_to_register.each do |data|
      instance_ids_array << data[:instance_id]
    end
    resp = client.describe_load_balancers(load_balancer_names: [elb_name])
    resp.load_balancer_descriptions.each do |elb_description|
      elb_description.instances.each do |instance|
        existing_instances.push(instance_id: instance.instance_id)
      end
    end
    client.register_instances_with_load_balancer(load_balancer_name: elb_name,
                                                 instances: instance_ids_to_register)
    instances_in_service = 0
    while instances_in_service < instance_ids_to_register.length
      sleep(10)
      instances_in_service = 0
      resp = client.describe_instance_health(
        load_balancer_name: elb_name
      )
      resp.instance_states.each do |instance_state|
        if instance_state.state == 'InService' && instance_ids_array.include?(instance_state.instance_id)
          instances_in_service += 1
        end
      end
    end
    unless existing_instances.empty?
      client.deregister_instances_from_load_balancer(load_balancer_name: elb_name,
                                                     instances: existing_instances)
    end
  end

  # Removes an instance from it's elb if an elb was found.
  # * +aws_instance+ - the instance to remove. must be an instance of the AwsInstance class.
  def self.remove_instance_from_elb(aws_instance)
    throw 'bad value' unless aws_instance.is_a?(AwsInstance)
    client = Helpers.CreateELB
    elbs = ELBClient.filter_elb_with_tags('Path-Name' => aws_instance.path_name, 'Environment' => aws_instance.environment.to_s)
    return false if elbs.empty?
    client.deregister_instances_from_load_balancer(load_balancer_name: elbs[0],
                                                   instances: [{ instance_id: aws_instance.aws_instance_data.instance_id }])
    true
  end

  # Adds an instance to it's elb if an elb was found.
  # * +aws_instance+ - the instance to add. must be an instance of the AwsInstance class.
  def self.add_instance_to_elb(aws_instance)
    throw 'bad value' unless aws_instance.is_a?(AwsInstance)
    client = Helpers.CreateELB
    elbs = ELBClient.filter_elb_with_tags('Path-Name' => aws_instance.path_name, 'Environment' => aws_instance.environment.to_s)
    return if elbs.empty?
    client.register_instances_with_load_balancer(load_balancer_name: elbs[0],
                                                 instances: [{ instance_id: aws_instance.aws_instance_data.instance_id }])
    checks = 0
    passed = false
    Helpers.log "inserting into #{elbs[0]}"
    while (checks < 24) && !passed
      resp = client.describe_instance_health(load_balancer_name: elbs[0])
      resp.instance_states.each do |instance_state|
        if (instance_state.state == 'InService') && (instance_state.instance_id == aws_instance.aws_instance_data.instance_id)
          passed = true
          break
        else
          sleep 10
          checks += 1
        end
      end
    end
    throw 'error inserting to elb' unless passed
    true
  end

  # Gets all the target groups with the tags. only works with v2 of
  # * +filters+ - a Hash containing
  # returns a Hash with all the Target groups found.
  def self.filter_groups_with_tags(filters)
    client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    resp = client.describe_target_groups(page_size: 399)
    found_groups = []
    aws_maximum_size = 20
    current_tg_index = 0
    target_groups = []

    begin
      all_groups_arn = []
      if aws_maximum_size < (resp.target_groups.length - current_tg_index)
        last_element_index = aws_maximum_size
      else
        last_element_index = resp.target_groups.length - current_tg_index
      end
      last_element_index += current_tg_index

      (current_tg_index...last_element_index).each do |tg_index|
        all_groups_arn << resp.target_groups[tg_index].target_group_arn
        target_groups << resp.target_groups[tg_index]
      end
      current_tg_index = last_element_index
      tags_resp = client.describe_tags(resource_arns: all_groups_arn)
      found_target_all_groups_arns = []
      tags_resp.tag_descriptions.each do |tag_description|
        matches = 0
        tag_description.tags.each do |tag|
          if filters.keys.include?(tag.key)
            if filters[tag.key] == tag.value
              matches += 1
            else
              next
              end
          else
            next
          end
          if matches == filters.length
            found_target_all_groups_arns << tag_description.resource_arn
          end
        end
      end
      found_target_all_groups_arns.each do |arn|
        target_groups.each do |tg|
          found_groups << tg if tg.target_group_arn == arn
        end
      end
    end while current_tg_index != resp.target_groups.length

    found_groups
  end

  # Removes instances from a target group (version 2 only)
  # * +instances_id+ - Array of hashes of instances to remove
  # * +group_arn+ - String the arn of the group.
  def self.remove_instances_from_group(instances_id, group_arn)
    client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    client.deregister_targets(target_group_arn: group_arn,
                              targets: instances_id)
  end

  # Removes an instance from a target group (version 2 only)
  # * +instance_id+ - AwsInstance to remove
  # * +group_arn+ - String the arn of the group.
  def self.remove_instance_from_group(instance)
    filters = instance.generate_filters_hash
    groups = ELBClient.filter_groups_with_tags(filters)
    throw "elb group wasn't found" if groups.empty?
    groups.each do |group|
      ELBClient.remove_instances_from_group [{ id: instance.get_aws_id }], group.target_group_arn
    end
  end

  # Removes an instance from a target group (version 2 only)
  # * +instances_id+ - Array of instances to remove
  # * +group_arn+ - String the arn of the group.
  def self.insert_instances_to_group(instances_id, group_arn, wait_for_confirmation = true)
    client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    wait_sleep_time = 10
    max_time_to_wait = 180
    time_waited = 0
    client.register_targets(target_group_arn: group_arn,
                            targets: instances_id)
    stripped_id = []
    instances_id.each do |instance_id|
      stripped_id << instance_id[:id]
    end
    if wait_for_confirmation
      healthy = 0
      until healthy == stripped_id.length
        sleep wait_sleep_time
        time_waited += wait_sleep_time
        resp = client.describe_target_health(target_group_arn: group_arn)
        resp.target_health_descriptions.each do |target_health_description|
          if stripped_id.include?(target_health_description.target.id)
            puts "checking status for #{target_health_description.target.id}:#{target_health_description.target_health.state}"
          end
          healthy += 1 if stripped_id.include?(target_health_description.target.id) &&
            (target_health_description.target_health.state == 'healthy'||target_health_description.target_health.state =='unused')
        end
        healthy = 0 if healthy < stripped_id.length
        throw 'Waited too long' if time_waited >= max_time_to_wait
      end
    end
  end

  def self.insert_instance_to_group(aws_instance)
    groups = ELBClient.filter_groups_with_tags(aws_instance.generate_filters_hash)
    throw "elb group wasn't found" if groups.empty?
    groups.each do |group|
      ELBClient.insert_instances_to_group [{ id: aws_instance.get_aws_id }], group.target_group_arn
    end
  end

  ## get_lb_healthcheck - gets the elb/alb healthcheck
  #  service_configuration - +hash+ service configuration from the service file
  # returns +string+ the healthcheck from the
  def self.get_lb_healthcheck(service_configuration)
    filters = {
      'Path-Name' => service_configuration['deployment']['path_name'],
      'Environment' => service_configuration[:environment],
      'Release' => 'yes',
      'Elb-Type' => service_configuration['deployment']['nginx_conf']
    }
    if service_configuration['deployment']['elb_version'] == 2
      groups = ELBClient.filter_groups_with_tags(filters)
      return '' if groups.nil? || groups.empty?
      return groups[0].health_check_path
    elsif service_configuration['deployment']['elb_version'] == 1 || service_configuration['deployment']['elb_version'].nil?
      elbs = ELBClient.get_elb_data_with_tags(filters)
      return '' if elbs.nil? || elbs.empty?
      elb_healthstring = elbs[0][:health_check][:target]
      position = elb_healthstring.index '/'
      return elb_healthstring[position..elb_healthstring.length]
    end
  end

  def self.update_group_instances(group_arn, instances_id)
    client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    resp = client.describe_target_health(target_group_arn: group_arn)
    old_instances = []
    resp.target_health_descriptions.each do |target_health_description|
      old_instances << { id: target_health_description.target.id }
    end
    ELBClient.insert_instances_to_group(instances_id, group_arn)
    ELBClient.remove_instances_from_group(old_instances, group_arn) unless old_instances.empty?
  end

  # generate alarm settings
  def self.generate_alarm_settings(groups)
    environment_arns = []
    tg_arns = []
    groups.each do |group|
      tg_arns << group.target_group_arn
    end
    alb_client = Aws::ElasticLoadBalancingV2::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)
    tags = alb_client.describe_tags(resource_arns: tg_arns).tag_descriptions
    groups.each do |target_group|
      info = { tg_arn: ELBClient.sanitize_tg_arn(target_group.target_group_arn),
               alb_arn: [],
               name: '' }
      tags.each do |tag_info|
        next unless tag_info.resource_arn == target_group.target_group_arn
        tag_values = {}
        tag_info.tags.each do |tag|
          tag_values[tag.key] = tag.value if tag.value != '/'
          tag_values[tag.key] = 'app' if tag.value == '/'
        end
        info[:name] = "#{tag_values['Environment']}-#{tag_values['Elb-Type']}-#{tag_values['Path-Name']}-#{tag_values['Domain']}-alrm" if tag_values['Domain']
        info[:name] = "#{tag_values['Environment']}-#{tag_values['Elb-Type']}-#{tag_values['Path-Name']}-alrm" if tag_values['Domain'].nil?
      end
      target_group.load_balancer_arns.each do |load_balancer_arn|
        info[:alb_arn] << ELBClient.sanitize_alb_arn(load_balancer_arn)
      end
      environment_arns << info
    end
    environment_arns
  end

  # adds an alarm to an environment using the action mentioned
  # * +environment_name+ - +String+ the environment name
  # * +alarm_action+ - +String+ the alarm arn
  def self.add_alarms(environment_name, alarm_action)
    cloudwatch_client = Aws::CloudWatch::Client.new(region: 'us-east-1', credentials: Helpers.create_aws_authentication_token)

    found_target_groups = ELBClient.filter_groups_with_tags('Environment' => environment_name, 'Version' => '2')
    alarms_information = ELBClient.generate_alarm_settings(found_target_groups)
    alarms_information.each do |alarm_information|
      Helpers.log "alarm on #{alarm_information[:name]}"
      cloudwatch_client.put_metric_alarm(
        alarm_name: alarm_information[:name], # required
        alarm_description: "alarm for #{environment_name} app",
        actions_enabled: true,
        alarm_actions: [alarm_action],
        # insufficient_data_actions: ["ResourceName"],
        namespace: 'AWS/ApplicationELB', # required
        statistic: 'Average', # required, accepts SampleCount, Average, Sum, Minimum, Maximum
        dimensions: [
          {
            name: 'LoadBalancer', # required
            value: alarm_information[:alb_arn][0], # required
          },
          {
            name: 'TargetGroup', # required
            value: alarm_information[:tg_arn], # required
          }
        ],
        metric_name: 'UnHealthyHostCount', # required
        period: 60, # required
        evaluation_periods: 2, # required
        threshold: 1.0, # required
        comparison_operator: 'GreaterThanOrEqualToThreshold'
      )
      Helpers.log "alarm on #{alarm_information[:name]} - done."
    end
  end
end
