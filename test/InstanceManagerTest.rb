require 'test/unit'
require_relative '../betterez/InstancesManager'
require_relative 'mocks/AwsInstanceMock'
class InstanceManagerTest < Test::Unit::TestCase
  def test_adding
    mgr = InstancesManager.new
    mgr.add_instance(AwsInstanceMock.new)
    results = mgr.get_instances_with_status('initial')
    assert(results.length == 1)
  end

  def test_updating
    mgr = InstancesManager.new
    instance = AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance, 'ready')
    results = mgr.get_instances_with_status('initial')
    assert(results.empty?)
    results = mgr.get_instances_with_status('ready')
    assert(results.length == 1)
  end

  def test_updating2
    mgr = InstancesManager.new
    instance = AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance, 'ready')
    results = mgr.get_instances_with_status('ready')
    assert(results.length == 1)
  end

  def test_updating3
    mgr = InstancesManager.new
    instance = AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance, 'ready')
    results = mgr.get_instances_with_status('ready')
    assert(results[0].get_aws_id == instance.get_aws_id)
  end

  def test_delete_with_status
    mgr = InstancesManager.new
    instances = []
    (0..4).each do |number|
      instances << AwsInstanceMock.new
      mgr.add_instance(instances[number])
    end
    mgr.update_instance_status(instances[0], 'ready')
    assert(mgr.get_instances_with_status('initial').length == instances.length - 1)
    mgr.delete_instances_with_status('initial')
    assert(mgr.get_instances_with_status('initial').empty?)
  end

  def test_instance_termination
    mgr = InstancesManager.new
    instance = AwsInstanceMock.new
    mgr.add_instance(instance)
    mgr.update_instance_status(instance, 'ready')
    assert(mgr.get_instances_with_status('ready')[0] == instance)
    instance2 = AwsInstanceMock.new
    mgr.add_instance(instance2)
    assert(mgr.get_instances_with_status('initial').length == 1)
    mgr.delete_and_terminate_instances_with_status('initial')
    assert(mgr.get_instances_with_status('initial').empty?)
  end

  def test_remove_instances_by_status
    mgr = InstancesManager.new
    instances = []
    (0..4).each do |number|
      instances << AwsInstanceMock.new
      mgr.add_instance(instances[number])
    end
    assert(mgr.get_all_instances_number == 5)
    mgr.update_instance_status(instances[0], 'ready')
    mgr.delete_instances_with_status('initial')
    assert(mgr.get_all_instances_number == 1)
  end

  def test_terminate_and_delete_all
    mgr = InstancesManager.new
    instances = []
    (0..4).each do |number|
      instances << AwsInstanceMock.new
      mgr.add_instance(instances[number])
    end
    assert(mgr.get_all_instances_number == 5)
    mgr.update_instance_status(instances[0], 'ready')
    mgr.update_instance_status(instances[1], 'ready')
    assert(mgr.get_instances_with_status('ready').length == 2)
    mgr.delete_and_terminate_all_instances
    assert(mgr.get_instances_with_status('ready').empty?)
    assert(mgr.get_all_instances_number == 0)
  end
end
