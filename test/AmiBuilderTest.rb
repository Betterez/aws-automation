require 'test/unit'
require_relative '../betterez/AmiBuilder'
require_relative '../betterez/InstancesManager'

class AmiBuilderMock
  attr_reader :status
  attr_accessor :create_ami_calls, :fail_create_ami

  def initialize
    @instance_id = "i-#{object_id}"
    @status = 'ready'
    @create_ami_calls = 0
    @fail_create_ami = false
  end

  def get_aws_id
    @instance_id
  end

  def create_ami(_service_setup_data)
    @create_ami_calls += 1
    raise 'ami creation failed' if @fail_create_ami
  end

  def terminate_instance
    @status = 'terminated'
  end
end

class AmiBuilderTest < Test::Unit::TestCase
  def test_ami_mode_launches_one_server_even_when_servers_count_is_two
    assert_equal(1, AmiBuilder.servers_to_launch(ami: true, servers_count: 2))
  end

  def test_ami_mode_launches_one_server_when_servers_count_is_one
    assert_equal(1, AmiBuilder.servers_to_launch(ami: true, servers_count: 1))
  end

  def test_debug_mode_without_ami_keeps_original_spare_launch_count
    assert_equal(10, AmiBuilder.servers_to_launch(debug: true, servers_count: 5))
  end

  def test_deploy_with_servers_count_two_launches_spares
    assert_equal(4, AmiBuilder.servers_to_launch(servers_count: 2))
  end

  def test_deploy_with_servers_count_one_keeps_default_three
    assert_equal(3, AmiBuilder.servers_to_launch(servers_count: 1))
  end

  def test_ami_mode_forces_servers_count_to_one
    data = { ami: true, servers_count: 2 }
    AmiBuilder.normalize_ami_server_count!(data)
    assert_equal(1, data[:servers_count])
  end

  def test_normalize_does_not_change_servers_count_without_ami_flag
    data = { ami: false, debug: true, servers_count: 2 }
    AmiBuilder.normalize_ami_server_count!(data)
    assert_equal(2, data[:servers_count])
  end

  def test_ensure_base_ami_raises_when_image_type_missing
    error = assert_raise(RuntimeError) do
      AmiBuilder.ensure_base_ami!(nil, nil)
    end
    assert_match(/machine\.image is missing/, error.message)
  end

  def test_ensure_base_ami_raises_when_ami_id_not_found
    error = assert_raise(RuntimeError) do
      AmiBuilder.ensure_base_ami!('node24130_arm64_nginx', nil)
    end
    assert_match(/no ami id for type node24130_arm64_nginx/, error.message)
  end

  def test_ensure_base_ami_passes_when_image_exists
    AmiBuilder.ensure_base_ami!('node24130_arm64_nginx', 'ami-123')
  end

  def test_ami_success_terminates_every_ready_instance
    manager = InstancesManager.new
    baker = AmiBuilderMock.new
    spare = AmiBuilderMock.new
    manager.add_instance(baker)
    manager.add_instance(spare)
    manager.update_instance_status(baker, InstancesManager::READY_STATUS)
    manager.update_instance_status(spare, InstancesManager::READY_STATUS)

    AmiBuilder.build_ami_and_terminate_builders(manager, { ami: true }, nil)

    assert_equal(1, baker.create_ami_calls)
    assert_equal('terminated', baker.status)
    assert_equal('terminated', spare.status)
    assert_equal(0, manager.get_all_instances_number)
  end

  def test_ami_failure_still_terminates_every_instance
    manager = InstancesManager.new
    baker = AmiBuilderMock.new
    baker.fail_create_ami = true
    spare = AmiBuilderMock.new
    manager.add_instance(baker)
    manager.add_instance(spare)
    manager.update_instance_status(baker, InstancesManager::READY_STATUS)
    manager.update_instance_status(spare, InstancesManager::READY_STATUS)

    assert_raise(RuntimeError) do
      AmiBuilder.build_ami_and_terminate_builders(manager, { ami: true }, nil)
    end

    assert_equal('terminated', baker.status)
    assert_equal('terminated', spare.status)
    assert_equal(0, manager.get_all_instances_number)
  end
end
