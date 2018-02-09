require_relative "../betterez/CommandParser"
require "test/unit"

class ParserTest <Test::Unit::TestCase
  
  def setup
    @parser=CommandParser.new
  end
  
  def test_default
    @parser.clear!
    assert(@parser.getServersData.length==0)
  end
  
  def test_bad_json
    assert_raise JSON::ParserError do
      @parser.command="hello"
    end
  end
  
  def test_good_json
    @parser.command='{"servers":[{"instance_private_ip":"www.test.com","serviceName":"test"}]}'
    assert(@parser.getServersData,"server date should not be nil")
    assert(@parser.getServersData[0][:instance_private_ip]=="www.test.com","address should match")
    assert(@parser.getServersData[0][:host_port]==3000,"default port should be 3000")
    assert(@parser.getServersData[0][:server_type]==:default,"if no server type was provided, default is assumed")
    assert(@parser.environment=="staging","default environment should be staging")
    assert(@parser.service_type=="ec2","default service_type should be ec2")
  end
  
  def test_server_with_port
    @parser.clear!
    @parser.command='{"servers":[{"instance_private_ip":"www.test.com","serviceName":"test","host_port":1234}]}'
    assert(@parser.getServersData[0][:host_port]==1234,"when port is provided, it should be used")
  end
  
  def test_add_server
    @parser.clear!
    assert(@parser.additional_servers.length==0,"no servers on clean object")
    @parser.addAdditionalServer({:instance_private_ip=>"qcwecqwe",:serviceName=>"some"})
    assert(@parser.additional_servers.length==1,"added server should be noticed")
    assert(@parser.getServersData[0][:server_type]==:default)
  end
  
  def test_bad_server_add
    @parser.clear!
    assert_raise ArgumentError do
      @parser.addAdditionalServer({:instance_private_ip=>"12.1.2.3"})
    end
  end
  
  def test_bad_server_add_2
    @parser.clear!
    assert_raise ArgumentError do
      @parser.addAdditionalServer({:instance_private_ip=>"12.1.2.3",:serviceName=> nil})
    end
  end
  
  def test_bad_server_add_3
    @parser.clear!
    assert_raise ArgumentError do
      @parser.addAdditionalServer({:instance_private_ip=>"12.1.2.3",:serviceName=> ""})
    end
  end
  
  def test_bad_server_add_4
    @parser.clear!
    assert_raise ArgumentError do
      @parser.addAdditionalServer({:instance_private_ip=>"",:serviceName=> "my service"})
    end
  end
  
  def test_servers_counting
    parser=CommandParser.new
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.1",:serviceName=>"/"})
    parser.addAdditionalServer({:instance_private_ip=>"10.1.1.2",:serviceName=>"/"})
    assert parser.getServersData().length==2
  end
  
  def test_default_values
    parser=CommandParser.new
    assert parser.environment=="staging"
    assert parser.service_type=="ec2"
  end
  
  def test_bad_service_type
    parser=CommandParser.new
    assert_raise ArgumentError do
      parser.service_type="test"
    end
  end
  
  def test_parameters_without_get_server
      parser=CommandParser.new
      parser.command='{"environment":"sandbox","servers":[]}'
      parser.addAdditionalServer({:instance_private_ip=>"1.1.1.1",:serviceName=>"my test"})
      #parser.getServersData
      assert(parser.environment=="sandbox","#{parser.environment} should be sandbox")      
  end
  
  def test_parameters_with_get_server    
      parser=CommandParser.new
      parser.command='{"environment":"sandbox","servers":[]}'
      parser.addAdditionalServer({:instance_private_ip=>"1.1.1.1",:serviceName=>"my test"})
      parser.getServersData
      assert(parser.environment=="sandbox","#{parser.environment} should be sandbox")      
  end
  
end