require 'aws-sdk'
require 'json'
## Helper module for betterez
module Helpers
  @@environment_values = nil
  # create an elb client
  def self.CreateELB(creation_region = 'us-east-1')
    creation_region = 'us-east-1' if creation_region.nil?
    Aws.config[:ssl_ca_bundle] = 'cacert.pem'
    elasticloadbalancing = Aws::ElasticLoadBalancing::Client.new(region: creation_region, credentials: Helpers.create_aws_authentication_token)
    elasticloadbalancing
  end

  ## create an ec2 client, load aws creds from settings file
  def self.create_aws_ec2_client(zone = 'us-east-1')
    zone = 'us-east-1' if zone.nil?
    Aws.config[:ssl_ca_bundle] = 'cacert.pem'
    Aws::EC2::Client.new(region: zone, credentials: Helpers.create_aws_authentication_token)
  end

  ## create a route53 object, load aws creds from settings file
  def self.create_aws_route53_client(creation_region = 'us-east-1')
    creation_region = 'us-east-1' if creation_region.nil?
    Aws.config[:ssl_ca_bundle] = 'cacert.pem'
    Aws::Route53::Client.new(region: creation_region, credentials: Helpers.create_aws_authentication_token)
  end

  ## Creates a S3 client, load aws creds from settings file
  def self.create_aws_S3_client(creation_region = 'us-east-1')
    creation_region = 'us-east-1' if creation_region.nil?
    Aws.config[:ssl_ca_bundle] = 'cacert.pem'
    Aws::S3::Client.new(region: creation_region, credentials: Helpers.create_aws_authentication_token)
  end

  ## creates aws authentication info
  def self.create_aws_authentication_token
    # authData = loadJSONData('settings/authentication.json')
    auth_file_name = 'settings/aws-auth.json'
    throw 'aws auth file does not exist!' unless File.exist?(auth_file_name)
    authData = loadJSONData(auth_file_name)
    rand = Random.new
    account = authData['accounts'][rand.rand(authData['accounts'].length)]
    puts "using #{account['name']}"
    account_creds = account['credentials']
    Aws::Credentials.new(account_creds['access_key_id'], account_creds['secret_access_key'])
  end

  def self.create_date_string
    Time.now.strftime('%Y_%m_%d')
  end

  def self.create_setup_data(environment, ami_type)
    result = {
      environment: environment.to_sym,
      infra_index: 0,
      build_number: '0',
      server_name: "#{ami_type}_#{environment}_#{create_time_date_string}_#{create_random_string 4}",
      nginx_conf: 'none',
      path_name: '',
      repo: 'na',
      service_type: ami_type,
      ami_type: ami_type
    }
    result
  end

  def self.create_time_date_string
    Time.now.strftime('%Y_%m_%d_%H_%M_%S')
  end

  def self.create_instance_stamp
    "#{Time.now.strftime('%Y_%m_%d_%H_%M')}_#{create_random_string 5}"
  end

  def self.validate_service(service)
    return false if service.nil? || service[:name].nil? || service[:repository].nil? ||
                    service[:face].nil? || service[:load].nil?
    return false if service[:load] > 100 || service[:load] < 1
    true
  end

  ###  loads json data from a file
  # * filename - the json file. `.json` is required.
  def self.loadJSONData(filename)
    return nil unless File.readable?(filename)
    fileData = JSON.parse(File.read(filename))
    fileData
  end

  def self.load_json_data_to_hash(filename)
    return nil unless File.readable?(filename)
    fileData = JSON.parse(File.read(filename), symbolize_names: true)
    fileData
  end

  ## outputs a message to the screen formatted with time.
  # * line - the message
  def self.log(line)
    puts("#{Time.new} - #{line}")
  end

  ## create a random text string with size length.
  # * size - the required size for the string
  def self.create_random_string(size)
    random_string = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
    value = ''
    seed = Random.new
    size = 5 if size.nil?
    for _ in 1..size do
      value += random_string[seed.rand(random_string.length)]
    end
    value
  end

  ## gets an instance id from the instance name
  # * +instance_name+ - string, the instance name to get the id for
  def self.get_instances_data_for_name(instance_name)
    instances = []
    client = Helpers.create_aws_ec2_client
    resp = client.describe_instances(filters: [
                                       name: 'tag:Name',
                                       values: [instance_name]
                                     ])
    resp.reservations.each do |reservation|
      reservation.instances.each do |instance_data|
        instances.push instance_data
      end
    end
    instances
  end

  def self.load_environment_values
    if @@environment_values.nil?
      puts "loading"
      @@environment_values = Helpers.load_json_data_to_hash('./settings/aws-auth.json')
    end
  end

  def self.get_cloud_ern
    load_environment_values
    @@environment_values[:aws][:cloud_watcher_arn]
  end

  #
  # # gets ssl certificate arn
  def self.get_cretificate_arn
    load_environment_values
    @@environment_values[:aws][:ssl_certificate_arn]
  end

  # get production public subnets
  def self.get_public_prodcution_subnets
    load_environment_values
    @@environment_values[:aws][:public_subnets]
  end

  # gets production security groups
  def self.get_production_security_groups_for_type(type)
    load_environment_values
    @@environment_values[:aws][:security_groups][type.to_sym]
  end

  def self.get_db_server_address_for_environment(environment)
    load_environment_values
    @@environment_values[:aws][:mongo_addresses][environment.to_sym]
  end
  # end of module
end
