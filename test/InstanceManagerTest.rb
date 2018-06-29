require "test/unit"
require_relative "../betterez/InstancesManager"
require_relative "mocks/AwsInstanceMock"
class InstanceManagerTest<Test::Unit::TestCase
  def test_adding
    mgr=InstancesManager.new
    mgr.add_instance(AwsInstanceMock.new)
    results=mgr.get_instances_with_status("initial")
    assert(results.length==1)
  end
  def test_updating
    mgr=InstancesManager.new
    instance=AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance,"ready")
    results=mgr.get_instances_with_status("initial")
    assert(results.length==0)
    results=mgr.get_instances_with_status("ready")
    assert(results.length==1)
  end
  def test_updating2
    mgr=InstancesManager.new
    instance=AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance,"ready")
    results=mgr.get_instances_with_status("ready")
    assert(results.length==1)
  end
  def test_updating3
    mgr=InstancesManager.new
    instance=AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance,"ready")
    results=mgr.get_instances_with_status("ready")
    assert(results[0].get_aws_id==instance.get_aws_id)
  end
  def test_delete_with_status
    mgr=InstancesManager.new
    instances=[]
    (0..4).each do |number|
      instances<<AwsInstanceMock.new
      mgr.add_instance(instances[number])
    end
    mgr.update_instance_status(instances[0],"ready")
    assert(mgr.get_instances_with_status("initial").length==instances.length-1)
    mgr.delete_instances_with_status("initial")
    assert(mgr.get_instances_with_status("initial").length==0)
  end
end
