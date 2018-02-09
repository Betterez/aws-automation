require "test/unit"
require_relative "../betterez/ConfigurationData"
require_relative "../betterez/CommandParser"
class ConfigurationTest <Test::Unit::TestCase
    
  def setup
    @parser=CommandParser.new
  end
  
  def test_ec2
    test_address="10.1.1.1"
    @parser.addAdditionalServer({:instance_private_ip=>test_address,:serviceName=>"my test"})
    tasks=@parser.getServersData
    conf=ConfigurationData.new(tasks,"sandbox",ConfigurationData::EC2)
    conf_data=conf.getConfigurationData 
    assert(conf_data[:tasks],"should have a tasks element.")
    assert(conf_data[:tasks].length==1,"adding this task should be reflected.")
    conf_data[:tasks].each do |task|
      assert(task[:filtered]==false,"default filter is off")
    end
    assert(conf_data[:tasks][0][:instance_private_ip]==test_address,"address should be the same")
    assert(conf_data[:tasks][0][:host_port]==3000,"default port should apply")
  end  
  
  def test_with_symbol
    parser=CommandParser.new
    parser.addAdditionalServer({:instance_private_ip=>"1.1.1.1",:serviceName=>"my test"})
    parser.addAdditionalServer({:instance_private_ip=>"2.3.4.44",:serviceName=>"app2"})
    parser.command='{"environment":"sandbox","servers":[{"instance_private_ip":"3.2.1.0","serviceName":"main"}]}'
    assert(parser.getServersData.length==3)
    conf=ConfigurationData.new(parser.getServersData,parser.environment,ConfigurationData::EC2)
    assert(conf.getConfigurationData)
    assert(conf.getConfigurationData[:lb])
    assert(conf.getConfigurationData[:lb]["server_ip"])
    assert(conf.getConfigurationData[:lb]["keys"])
  end
    
end