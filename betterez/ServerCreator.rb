require('open3')
require_relative  'Helpers'
require_relative  'ELBClient'
require_relative 'NginxConfigurator'
require_relative 'AwsInstance'
require_relative 'NilNotifire'

# Create a server on aws.
class ServerCreator
    attr_accessor :notifire
    # Constructing this object
    # * settings - hash storing the json settings file and the required environment
    def initialize(settings)
        @params = settings
        @notifire = NilNotifire.new
    end

    def to_s
        "ServerCreator\r\nparams:#{@params}"
    end

    # generates server name
    # * service_setup_data - a hash contains the server's data
    def create_server_name(service_setup_data)
        t = Time.new
        "#{service_setup_data[:repo]}_#{sprintf('%d_%.2d_%.2d', t.year, t.month, t.day)}_#{Helpers.create_random_string(5)}"
    end

    def notify(message)
        @notifire.notify(0, message) if @notifire
    end

    # creates a server(s) with the supplied information
    # * service_setup_data - a hash contains the server's data
    def create_instances_from_parameters(service_setup_data)
        servers = AwsInstance.create_aws_instances(service_setup_data, @params, @notifire)
        if !servers.empty?
            notify('server created!')
        else
            notify('fail to create servers')
        end
        servers
    end

    def create_servers_from_parameters(service_setup_data)
        throw "healthcheck doesn't match" if check_service_setup_healthcheck(service_setup_data)==false
        update_service_setup_data(service_setup_data)
        servers = create_instances_from_parameters(service_setup_data)
        throw 'error creating servers' if servers.nil? || servers.empty?
        if service_setup_data[:dont_push_to_lb]
          notify("seems to be test server(s), we're not pushing to alb.")
        else
          if servers[0].is_elb_instance?
              deploy_to_elb(service_setup_data, servers)
          elsif servers[0].is_nginx_instance?
              deploy_to_nginx(service_setup_data)
              notify('nginx elb status instance')
          else
              notify('unknown elb status for this instance')
          end
        end
    end
    def update_service_setup_data(service_setup_data)
      if !service_setup_data['deployment']['balancer_configuration'] && service_setup_data['deployment']['nginx_conf']
        service_setup_data['deployment']['balancer_configuration'] = service_setup_data['deployment']['nginx_conf']
      end
    end

    def check_service_setup_healthcheck(service_setup_data)
      if service_setup_data["deployment"]["healthcheck"]["perform"]==true
        rg=Regexp.compile("\/[\/a-z]+")
        return rg.match(service_setup_data["deployment"]["healthcheck"]["command"]).to_s == ELBClient.get_lb_healthcheck(service_setup_data)
      end
      nil
    end

    def create_or_update_server(service_setup_data)
      if check_service_setup_healthcheck(service_setup_data)==false
        puts ""
        puts "WARNING healthcheck may fail deployment - lb and service file discrepancy"
        puts "WARNING healthcheck #{service_setup_data["deployment"]["healthcheck"]["command"]} no responding to #{ELBClient.get_lb_healthcheck(service_setup_data)}"
        puts ""
      end
      update_service_setup_data service_setup_data
        notify('looking for instances...')
        aws_filters = [{ name: 'tag:Environment', values: [service_setup_data[:environment].to_s] },
                       { name: 'tag:Repository', values: [service_setup_data['deployment']['service_name']] },
                       { name: 'instance-state-name', values: ['running'] }]
        instances = AwsInstance.get_instances_with_filters(aws_filters, @params)
        notify("found #{instances.length} instance(s).")
        instances_out_of_date = []
        instances_up_to_date = []
        instances.each do |instance|
            instance.notifire = @notifire
            if instance.is_ami_version_up_to_date(service_setup_data['machine']['image'])
                instances_up_to_date.push(instance)
            else
                instances_out_of_date.push(instance)
            end
        end
        if !instances_up_to_date.empty? && (service_setup_data[:servers_count].nil? || instances_up_to_date.length >= service_setup_data[:servers_count])
            limiter = Random.new
            notify("#{instances_up_to_date.length} instance(s) up to date!")
            service_setup_data[:install_type] = :existing_servers
            service_setup_data['deployment']['elb_version'] = 1 unless service_setup_data['deployment'].key? 'elb_version'
            instance_threads = []
            AwsInstance.run_pci_dss_check(service_setup_data,@params)
            instances_up_to_date.each do |instance|
                sleep ( 0.1+limiter.rand(2000)/100 )
                instance_threads << Thread.new do
                    if instance.is_elb_instance?
                        notify 'removing from elb'
                        ELBClient.remove_instance_from_elb(instance) if service_setup_data['deployment']['elb_version'] == 1
                        ELBClient.remove_instance_from_group(instance) if service_setup_data['deployment']['elb_version'] == 2
                    end
                    notify("updating code base and restarting for #{instance.aws_instance_data.instance_id}")
                    notify(instance.update_instance_code(service_setup_data))
                    notify("done, updating Build Number to #{service_setup_data[:build_number]}...")
                    notify(instance.update_build_number(service_setup_data[:build_number]))
                    notify('updating init file...')
                    notify("done with #{instance.update_init_file_and_restart service_setup_data}")
                    notify('updating logger config...')
                    notify("done with #{instance.update_logger_config service_setup_data}")
                    boundery = 0
                    until instance.is_service_healthy?(service_setup_data)
                        notify 'waiting for service to be up'
                        sleep 10
                        boundery += 1
                        exit 1 if boundery > 10
                    end
                    notify 'service healthy.'
                    if instance.is_elb_instance?&service_setup_data[:debug]
                      notify 'skipping elb'
                    elsif instance.is_elb_instance?
                        notify 'inserting to elb'
                        ELBClient.add_instance_to_elb(instance) if service_setup_data['deployment']['elb_version'] == 1
                        ELBClient.insert_instance_to_group(instance) if service_setup_data['deployment']['elb_version'] == 2
                    end
                    notify('done.')
                end
            end
            instance_threads.each(&:join)
            if service_setup_data[:service_type] == 'http' && service_setup_data[:balancer_configuration] == 'api'
                notify('done setting up api server')
            end
            notify('done all. ')
        else
            notify('instance(s) out of date or number. creating new one(s)')
            update_service_setup_data(service_setup_data)
            created_servers = create_instances_from_parameters(service_setup_data)
            if created_servers.empty?
                notify('error creating servers')
                throw 'error creating servers'
            end
            if service_setup_data[:dont_push_to_lb]
              notify  "not pushing updated server to an elb."
            elsif service_setup_data['deployment']['service_type'] == 'http' &&(
                  service_setup_data['deployment']['balancer_configuration'] != 'none'||
                  service_setup_data['deployment']['balancer_configuration'] != 'worker'
                  )
                deploy_to_elb(service_setup_data,created_servers)
            end
        end
    end

    def deploy_to_nginx(service_setup_data)
        api_servers = []
        nginx_servers = AwsInstance.get_instances_with_filters([
                                                                   { name: 'tag:Environment', values: [service_setup_data[:environment]] },
                                                                   { name: 'tag:Nginx-Configuration', values: ['api'] },
                                                                   { name: 'tag:Service-Type', values: ['nginx'] },
                                                                   { name: 'instance-state-name', values: ['running'] }
                                                               ], @params)
        if nginx_servers.empty?
            throw "no nginx found for api in #{service_setup_data[:environment]}"
        end
        notify('nginx server(s) found, looking for current servers...')
        existing_servers = AwsInstance.get_instances_with_filters([
                                                                      { name: 'tag:Environment', values: [service_setup_data[:environment]] },
                                                                      { name: 'tag:Nginx-Configuration', values: ['api'] },
                                                                      { name: 'tag:Service-Type', values: ['http'] },
                                                                      { name: 'instance-state-name', values: ['running'] }
                                                                  ], @params)

        existing_servers.each do |instance|
            instance_data = { instance_id: instance.aws_instance_data.instance_id,
                              instance_private_ip: instance.aws_instance_data.private_ip_address,
                              build_number: 0 }
            instance_data[:serviceName] = instance.path_name
            instance_data[:host_port] = instance.host_port
            instance_data[:build_number] = instance.build_number
            api_servers.push(instance_data)
        end
        notify("#{api_servers.length} servers found.")
        api_servers = ServerCreator.arrange_only_last_servers(api_servers)
        notify("#{api_servers.length} servers remains after build reduction.")
        conf = NginxConfigurator.new(server_name: 'api')
        nginx_servers.each do |server|
            upload_config = {
                lb: { 'server_ip' => server.get_access_ip,
                      'keys' => @params[service_setup_data[:environment].to_sym][:keyPath] },
                tasks: api_servers
            }
            notify("pushing new configuration to nginx #{server.aws_instance_data.instance_id}")
            conf.uploadNewConfigurations(upload_config)
            notify('done.')
        end
        nginx_servers
    end

    # removes servers that have old build_number
    def self.arrange_only_last_servers(servers)
        arranged_servers = []
        servers_hash = {}
        servers.each do |server|
            if servers_hash.keys.include?(server[:serviceName])
                if server[:build_number] > servers_hash[server[:serviceName]] [:build_number]
                    servers_hash[server[:serviceName]] = server
                end
            else
                servers_hash[server[:serviceName]] = server
            end
        end
        servers.each do |server|
            if server[:build_number] == servers_hash[server[:serviceName]][:build_number]
                arranged_servers.push(server)
            end
        end
        arranged_servers
    end

    def deploy_to_elb(service_setup_data, servers)
        service_setup_data['deployment']['elb_version'] = 1 unless service_setup_data['deployment'].key? 'elb_version'
        notify "elb type to deploy:#{service_setup_data['deployment']['elb_version']}"
        elb_filters = { 'Environment' => service_setup_data[:environment],
                        'Path-Name' => service_setup_data['deployment']['path_name'],
                        'Release' => 'yes',
                        'Elb-Type' => service_setup_data['deployment']['balancer_configuration'] }
        instance_ids1 = []
        instance_ids2 = []
        servers.each do |server|
            instance_ids1 << { instance_id: server.aws_instance_data.instance_id }
            instance_ids2 << { id: server.aws_instance_data.instance_id }
        end
        if service_setup_data['deployment']['elb_version'] == 1
            elbs = ELBClient.filter_elb_with_tags(elb_filters)
            throw 'no elb found' if nil == elbs || elbs.empty?
            notify "deploying to the following elbs:#{elbs}"
            elbs.each do |elb_name|
                notify("deploying #{instance_ids1} to elb #{elb_name}")
                ELBClient.update_elb_instances(elb_name, instance_ids1)
            end
        elsif service_setup_data['deployment']['elb_version'] == 2
            groups = ELBClient.filter_groups_with_tags(elb_filters)
            groups.each do |group|
                notify "updating group #{group.target_group_name} with #{instance_ids2}"
                ELBClient.update_group_instances(group.target_group_arn, instance_ids2)
                notify 'done'
            end
        elsif service_setup_data['deployment']['elb_version'] == 0
          notify "no elb is configured"
        else
            throw 'unknown elb version!'
        end
        notify('servers deployed and running.')
    end
end
