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
require_relative '../betterez/VaultDriver'

class AwsInstanceLoggerConfigTest < Test::Unit::TestCase
  InstanceMock = Struct.new(:instance_id, :instance_type, :tags)

  class TestableAwsInstance < AwsInstance
    def initialize
      instance = InstanceMock.new('i-test', 't4g.small', [])
      super(instance, { sandbox: { keyPath: '/tmp/key' } })
    end
  end

  def setup
    @instance = TestableAwsInstance.new
    @vault_calls = []
    @original_from_secrets_file = VaultDriver.method(:from_secrets_file)
    vault_calls = @vault_calls
    VaultDriver.define_singleton_method(:from_secrets_file) do |*args|
      vault_calls << args
      raise 'VaultDriver.from_secrets_file should not be called'
    end
  end

  def teardown
    VaultDriver.define_singleton_method(:from_secrets_file, @original_from_secrets_file)
  end

  def test_update_logger_config_skips_vault_when_use_secrets_manager
    result = @instance.update_logger_config(use_secrets_manager: true, environment: 'sandbox')

    assert_equal('skipped', result)
    assert_equal([], @vault_calls)
  end
end
