require "test/unit"
require_relative "../betterez/InstancesManager"
class InstanceManagerTest<Test::Unit::TestCase
  def test_adding
    mgr=InstancesManager.new
    mgr.add_instance("123456")
    results=mgr.get_instances_with_status("initial")
    assert(results.length==1)
    assert(results[0]=="123456")
  end
  def test_updating
    mgr=InstancesManager.new
    mgr.add_instance("123456")
    mgr.update_instance_status("123456","ready")
    results=mgr.get_instances_with_status("initial")
    assert(results.length==0)
  end
  def test_updating2
    mgr=InstancesManager.new
    mgr.add_instance("123456")
    mgr.update_instance_status("123456","ready")
    results=mgr.get_instances_with_status("ready")
    assert(results.length==1)
  end
  def test_updating3
    mgr=InstancesManager.new
    mgr.add_instance("123456")
    mgr.update_instance_status("123456","ready")
    results=mgr.get_instances_with_status("ready")
    assert(results[0]=="123456")
  end
end
