# frozen_string_literal: true

require 'test/unit'

$LOADED_FEATURES << 'net/ssh' unless $LOADED_FEATURES.include?('net/ssh')
$LOADED_FEATURES << 'net/scp' unless $LOADED_FEATURES.include?('net/scp')

unless defined?(Net::SSH)
  module Net
    module SSH
      def self.start(*)
        yield self
      end

      def self.scp
        self
      end

      def self.upload!(*); end
      def self.exec!(*); end
    end

    module SCP
      def self.upload!(*); end
    end
  end
end

require_relative '../betterez/AwsInstance'

class AwsInstanceSshTest < Test::Unit::TestCase
  InstanceMock = Struct.new(:instance_id, :instance_type, :tags, :public_ip_address, :private_ip_address)

  class FakeSession
    def initialize(output, exit_code)
      @output = output
      @exit_code = exit_code
    end

    def exec!(_command, status: nil)
      status[:exit_code] = @exit_code if status
      @output
    end
  end

  def setup
    @instance = AwsInstance.new(InstanceMock.new('i-test', 't4g.small', [], nil, '10.0.0.1'), { staging: { keyPath: '/tmp/key' } })
    @instance.environment = 'staging'
    @original_start = Net::SSH.method(:start)
  end

  def teardown
    Net::SSH.define_singleton_method(:start, @original_start)
  end

  # Each element of +outcomes+ is either an exception to raise or a FakeSession to yield.
  def stub_ssh(outcomes)
    calls = []
    Net::SSH.define_singleton_method(:start) do |*args, **_opts, &block|
      calls << args
      outcome = outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      block.call(outcome)
    end
    calls
  end

  def test_run_ssh_command_stops_retrying_after_success_following_failure
    calls = stub_ssh([StandardError.new('refused'), FakeSession.new('ok', 0), FakeSession.new('again', 0)])

    result = @instance.run_ssh_command('ls', 5, 0)

    assert_equal('ok', result)
    assert_equal(2, calls.length)
  end

  def test_run_ssh_command_bang_returns_output_on_success
    stub_ssh([FakeSession.new('57', 0)])

    assert_equal('57', @instance.run_ssh_command!('echo 57', 1, 0))
  end

  def test_run_ssh_command_bang_raises_on_non_zero_exit
    stub_ssh([FakeSession.new('permission denied', 1)])

    error = assert_raise(RuntimeError) { @instance.run_ssh_command!('false', 1, 0) }
    assert_match(/exit code 1/, error.message)
  end

  def test_run_ssh_command_bang_retries_connection_errors_then_raises
    calls = stub_ssh([StandardError.new('refused'), StandardError.new('refused')])

    error = assert_raise(RuntimeError) { @instance.run_ssh_command!('ls', 2, 0) }
    assert_match(/refused/, error.message)
    assert_equal(2, calls.length)
  end

  def test_run_ssh_command_bang_retries_connection_error_then_succeeds
    stub_ssh([StandardError.new('refused'), FakeSession.new('ok', 0)])

    assert_equal('ok', @instance.run_ssh_command!('ls', 3, 0))
  end

  def test_write_build_number_file_raises_when_build_number_missing
    [nil, '', '  '].each do |missing|
      assert_raise(ArgumentError) { @instance.write_build_number_file(missing) }
    end
  end

  def test_write_build_number_file_writes_zero
    commands = []
    @instance.define_singleton_method(:run_ssh_command!) do |command, *|
      commands << command
      ''
    end

    @instance.write_build_number_file('0')

    assert_equal(['echo 0 | sudo tee /home/bz-app/build_number.txt'], commands)
  end

  def test_update_build_number_does_not_write_build_number_file
    commands = []
    instance = @instance
    instance.define_singleton_method(:run_ssh_command) do |command, *|
      commands << command
      ''
    end
    instance.define_singleton_method(:run_ssh_command!) do |command, *|
      commands << command
      ''
    end
    ec2 = Object.new
    def ec2.create_tags(**); end
    original_client = Helpers.method(:create_aws_ec2_client)
    Helpers.define_singleton_method(:create_aws_ec2_client) { |*| ec2 }
    begin
      instance.update_build_number(
        {
          build_number: 57,
          'applications' => [{ 'deployment' => { 'service_name' => 'svc' }, 'machine' => { 'daemon_type' => 'systemd' } }]
        }
      )
    ensure
      Helpers.define_singleton_method(:create_aws_ec2_client, original_client)
    end

    assert(commands.none? { |c| c.include?('build_number.txt') })
    assert(commands.include?('sudo systemctl restart svc.service'))
  end
end
