require_relative 'AwsInstance'
require_relative 'Helpers'
require_relative 'Notifire'
require_relative 'ELBClient'

class InstancesCleaner
  attr_accessor(:notifire)
  attr_accessor(:remove_instances)
  def initialize(settings)
    @settings = settings
    @remove_instances=true
  end

  def notify(notification)
    @notifire.notify(1, notification) if @notifire
  end

  # Removes out of date instance from the cluster.
  # * +environment+ - +string+ the cluster environment
  # * +type+ - +string+ the type of the instances to check
  def clean(cleaning_options)
    suitable_aws_instances = nil
    filters = [
      { name: 'tag:Environment', values: [cleaning_options[:environment]] },
      { name: 'instance-state-name', values: ['running'] }
    ]
    if cleaning_options[:type] == 'api'
      filters.push(
        { name: 'tag:Nginx-Configuration', values: ['api'] },
        name: 'tag:Service-Type', values: ['http'])
    elsif cleaning_options[:type] == 'app'
      filters.push(
        { name: 'tag:Nginx-Configuration', values: ['app'] },
        name: 'tag:Service-Type', values: ['http'])
    elsif cleaning_options[:type] == 'worker'
      filters.push(name: 'tag:Service-Type', values: ['worker'])
    elsif cleaning_options[:type] == 'webadmin'
      filters.push(
        { name: 'tag:Nginx-Configuration', values: ['webadmin'] },
        name: 'tag:Service-Type', values: ['http'])  
    end
    suitable_aws_instances = AwsInstance.get_instances_with_filters(filters, @settings)
    notify "found #{suitable_aws_instances.length} instances"
    instances_to_remove = get_out_of_date_instances(suitable_aws_instances, cleaning_options[:build_delta])
    notify "#{instances_to_remove.length} instances remain after built filtering:\r\n"
    if  instances_to_remove.length == 0
      notify "nothing to remove."
      return 0
    end
    if cleaning_options[:type] == 'app' || cleaning_options[:type] == "api" || cleaning_options[:type] == "webadmin"
      notify 'cheking for apps in elbs...'
      instances_currently_in_target_groups = ELBClient.list_all_instances_in_target_groups_with_tag_filters({
        'Environment' => cleaning_options[:environment], 'Elb-Type' => cleaning_options[:type], })
      trimmed_remove_list = []
      instances_to_remove.each do |removeable_instance|
        next if instances_currently_in_target_groups.include?(removeable_instance.aws_instance_data.instance_id)
        trimmed_remove_list.push(removeable_instance)
      end
      instances_to_remove=trimmed_remove_list
      if(instances_to_remove.length>0)
        notify "need to remove #{instances_to_remove.length} instances: "
      else
        notify "nothing to remove."
        return 0
      end
    end
    if cleaning_options[:view_only]==true
      notify  "need to be removed:\r\n"
    end
    instances_to_remove.each do |removeable_instance|
      if cleaning_options[:view_only]==false
        notify("removing #{removeable_instance}")
        removeable_instance.terminate_instance
      else
        notify "#{removeable_instance}"
      end
    end
    instances_to_remove.length
  end

  # gets the minimum build number per repository
  # * +instances+ - Array of id  +strings+
  def get_minimum_build_numbers_from_instances(instances)
    instances_hash = {}
    instances.each do |instance|
      if nil == instances_hash[instance.repository]
        instances_hash[instance.repository]=instance.build_number
      elsif instances_hash[instance.repository]>instance.build_number
        instances_hash[instance.repository]=instance.build_number
      end
    end
      instances_hash
  end

  # Gets an Array of out of date (by build number) instances from an existing Array.
  # * +suitable_aws_instances+ - +Array+ raw instances to check from
  # * +number_delta+ - +Number+ if bigger then 0, old instances will be kept up to number_delta behind.
  def get_out_of_date_instances(suitable_aws_instances, number_delta)
    instances_hash = {}
    last_build_number = 0
    instances_to_remove = []
    suitable_aws_instances.each do |aws_instance|
      next if nil == aws_instance.repository
      next if aws_instance.immune
      next if aws_instance.build_number == "000"
      if nil == instances_hash[aws_instance.repository]
        instances_hash[aws_instance.repository] = []
        notify "adding #{aws_instance.repository} to the list"
      end
      instances_hash[aws_instance.repository].push(aws_instance)
    end
    instances_hash.keys.each do |repo|
      instances_hash[repo].sort!{|x,y| y.build_number<=>x.build_number}
      notify "#{instances_hash[repo].length} items in #{repo}, last build number:#{instances_hash[repo][0].build_number}"
    end
    instances_hash.keys.each do |repo|
      next unless instances_hash[repo].length > 1
      last_build_number=instances_hash[repo][0].build_number
      last_known_build_number=last_build_number
      index = 0
      instances_hash[repo].each do |repo_instance|
        if(repo_instance.build_number < last_known_build_number)
          index+=1
          last_known_build_number=repo_instance.build_number
        end
        instances_to_remove.push(repo_instance) if index > number_delta
      end
    end
    instances_to_remove
  end

  private :notify
end
