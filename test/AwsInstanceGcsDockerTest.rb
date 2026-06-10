# frozen_string_literal: true

require 'test/unit'
require 'fileutils'

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
require_relative '../betterez/GoogleCloudStorage'

class AwsInstanceGcsDockerTest < Test::Unit::TestCase
  InstanceMock = Struct.new(:instance_id, :instance_type, :tags)

  class TestableAwsInstance < AwsInstance
    attr_reader :uploads, :commands, :notifications

    def initialize
      @uploads = []
      @commands = []
      @notifications = []
      instance = InstanceMock.new('i-test', 't4g.small', [])
      super(instance, { staging: { keyPath: '/tmp/key' } })
    end

    def notify(message)
      @notifications << message
    end

    def upload_file_to_host(local_path, remote_path)
      @uploads << [local_path, remote_path]
    end

    def run_ssh_command(command, _loops = 5, _delay = 5)
      @commands << command
      ''
    end

    def run_queued_ssh_command(command, _run_in_terminal)
      @commands << command
    end
  end

  def setup
    @instance = TestableAwsInstance.new
    @temp_dir = "temp/gcs_docker_test_#{Process.pid}/"
    FileUtils.mkdir_p(@temp_dir)
    @local_tar = File.join(@temp_dir, GoogleCloudStorage::DOCKER_IMAGE_FILENAME)
    File.write(@local_tar, 'docker-tar')

    @original_download = GoogleCloudStorage.method(:download_latest_file_of_bucket)
    GoogleCloudStorage.define_singleton_method(:download_latest_file_of_bucket) do |_bucket, _dir, output_dir|
      File.join(output_dir, GoogleCloudStorage::DOCKER_IMAGE_FILENAME)
    end
  end

  def teardown
    GoogleCloudStorage.define_singleton_method(:download_latest_file_of_bucket, @original_download)
    FileUtils.rm_rf(@temp_dir)
  end

  def app_entry
    {
      'deployment' => {
        'service_name' => 'btrz-api-bpes-java',
        'source' => {
          'type' => 'gcs_docker',
          'bucket' => 'artifacts',
          'dir_name' => 'builds/'
        }
      },
      'machine' => { 'install' => ['docker load -i image.tar'] }
    }
  end

  def test_gcs_docker_uploads_image_tar_to_app_dir
    @instance.load_single_application_code(
      { build_number: 42 },
      app_entry,
      false,
      @temp_dir
    )

    assert_equal(1, @instance.uploads.length)
    assert_equal(@local_tar, @instance.uploads[0][0])
    assert_equal('/home/ubuntu/image.tar', @instance.uploads[0][1])

    assert(@instance.commands.any? { |c| c.include?('mkdir -p /home/bz-app/btrz-api-bpes-java') })
    assert(@instance.commands.any? { |c| c == 'sudo mv /home/ubuntu/image.tar /home/bz-app/btrz-api-bpes-java/' })
    assert(@instance.commands.any? { |c| c.include?('chown -R bz-app:bz-app /home/bz-app/btrz-api-bpes-java') })
    assert(@instance.commands.any? { |c| c.include?('echo 42') })
    assert(@instance.commands.none? { |c| c.include?('tar -xzf') })
  end

  def test_gcs_docker_requires_bucket_and_dir_name
    assert_raise(ArgumentError) do
      @instance.load_single_application_code(
        {},
        {
          'deployment' => {
            'service_name' => 'svc',
            'source' => { 'type' => 'gcs_docker' }
          },
          'machine' => {}
        },
        false,
        @temp_dir
      )
    end
  end
end
