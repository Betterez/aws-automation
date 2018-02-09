require "test/unit"
require_relative  "../betterez/ServerCreator"
class ServerCreatorTest <Test::Unit::TestCase

  def test_server_reduction
    client=ServerCreator.new({settings_file: "./settings/aws-data.json"})
    servers=[
      {build_number: 1,serviceName: "test"},
      {build_number: 2,serviceName: "test"},
      {build_number: 4,serviceName: "test"},
      {build_number: 6,serviceName: "test"},
      {build_number: 7,serviceName: "test"},
    ]
    servers=ServerCreator.arrange_only_last_servers(servers)
    assert(servers.length==1)
    assert(servers[0][:build_number]==7)
  end

end
