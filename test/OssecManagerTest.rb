require "test/unit"
require_relative "../betterez/OssecManager"

class OssecManagerTest  < Test::Unit::TestCase
  def test_server_conf
    manger=OssecManager.new "sandbox"
    puts "#{manger.username},#{manger.password}"
    results=manger.list_all_agents
    puts results
  end
end
