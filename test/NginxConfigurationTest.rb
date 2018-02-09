require "test/unit"
require_relative "../betterez/ConfigurationData"
require_relative "../betterez/NginxConfigurator"
require_relative "../betterez/CommandParser"

class NginxConfigurationTest < Test::Unit::TestCase
  def test_configuration_with_default
    parser=CommandParser.new
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.1",:serviceName=>"test_service"})
    tasks=parser.getServersData
    conf=ConfigurationData.new(tasks,"sandbox",ConfigurationData::EC2)
    conf_data=conf.getConfigurationData
    nc=NginxConfigurator.new 
    nginx_data=nc.generateConfigData(conf_data)
    assert(nginx_data.include?("server 10.1.1.1"),"see that the server is there")
    assert(nginx_data.include?("upstream test_service"),"see that the server is there")
    assert(nginx_data.include?("location /test_service/"),"see that the server is there")
    assert(nginx_data.include?("proxy_pass http://test_service;"),"see that the server is there")
  end
  def test_configuration_with_root
    parser=CommandParser.new
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.1",:serviceName=>"/"})
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.2",:serviceName=>"/"})
    tasks=parser.getServersData
    conf=ConfigurationData.new(tasks,"sandbox",ConfigurationData::EC2)
    conf_data=conf.getConfigurationData
    nc=NginxConfigurator.new 
    nginx_data=nc.generateConfigData(conf_data)
    assert(nginx_data.include?("server 10.1.1.1"),"see that the server is there")
    assert(nginx_data.include?("upstream #{NginxConfigurator::ROOT_NAME}"),"root app has one name")
    assert(nginx_data.include?("location / {"),"server root ")
    assert(nginx_data.include?("proxy_pass http://#{NginxConfigurator::ROOT_NAME};"),"see that the server is there")
  end

  def test_configuration_with_servers
    parser=CommandParser.new
    parser.command='{"environment":"sandbox","service_type":"ec2"}'
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.1",:serviceName=>"/"})
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.2",:serviceName=>"bule"})
    tasks=parser.getServersData
    conf=ConfigurationData.new(tasks,parser.environment,ConfigurationData::EC2)
    conf_data=conf.getConfigurationData
    nc=NginxConfigurator.new 
    nginx_data=nc.generateConfigData(conf_data)
    assert(nginx_data.include?("server 10.1.1.1"),"see that the server is there")
    assert(nginx_data.include?("server 10.1.1.2"),"see that the server is there")
  end
  
  def test_bad_configuration
    parser=CommandParser.new
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.1",:serviceName=>"/"})
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.2",:serviceName=>"/"})
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.2",:serviceName=>"/"})
    tasks=parser.getServersData
    conf=ConfigurationData.new(tasks,"sandbox",ConfigurationData::EC2)
    conf_data=conf.getConfigurationData
    nc=NginxConfigurator.new 
    assert_raise ArgumentError do 
      nginx_data=nc.generateConfigData(conf_data)
    end
  end  
end