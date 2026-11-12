# frozen_string_literal: true

require 'test/unit'
require 'fileutils'

$LOADED_FEATURES << 'net/ssh' unless $LOADED_FEATURES.include?('net/ssh')
$LOADED_FEATURES << 'net/scp' unless $LOADED_FEATURES.include?('net/scp')
$LOADED_FEATURES << 'aws-sdk' unless $LOADED_FEATURES.include?('aws-sdk')
$LOADED_FEATURES << 'aws-sdk-secretsmanager' unless $LOADED_FEATURES.include?('aws-sdk-secretsmanager')

unless defined?(Aws)
  module Aws
    module EC2
      class Client; end
    end
    module S3
      class Client; end
    end
    module ElasticLoadBalancing
      class Client; end
    end
    module ElasticLoadBalancingV2
      class Client; end
    end
    module Route53
      class Client; end
    end
    module SecretsManager
      class Client; end
    end
    class InstanceProfileCredentials; end
    def self.config
      @config ||= {}
    end
  end
end

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

require_relative '../betterez/GithubReleaseInstaller'
require_relative '../betterez/AwsInstance'

class GithubReleaseInstallerTest < Test::Unit::TestCase
  InstanceMock = Struct.new(:instance_id, :instance_type, :tags)

  class FakeInstance
    attr_reader :data_uploads, :commands, :notifications, :build_numbers

    def initialize
      @data_uploads = []
      @commands = []
      @notifications = []
      @build_numbers = []
    end

    def notify(message)
      @notifications << message
    end

    def upload_data_to_file(data, remote_file_name)
      @data_uploads << [data, remote_file_name]
    end

    def run_ssh_command!(command, _loops = 5, _delay = 5)
      @commands << command
      ''
    end

    def write_build_number_file(build_number)
      @build_numbers << build_number
      @commands << "echo #{build_number} | sudo tee /home/bz-app/build_number.txt"
    end
  end

  class TestableAwsInstance < AwsInstance
    attr_reader :uploads, :data_uploads, :commands, :notifications

    def initialize
      @uploads = []
      @data_uploads = []
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

    def upload_data_to_file(data, remote_file_name)
      @data_uploads << [data, remote_file_name]
    end

    def run_ssh_command(command, _loops = 5, _delay = 5)
      @commands << command
      ''
    end

    def run_ssh_command!(command, _loops = 5, _delay = 5)
      @commands << command
      ''
    end

    def run_queued_ssh_command(command, _run_in_terminal)
      @commands << command
    end

    def run_ssh_command_with_status(command)
      @commands << command
      ''
    end
  end

  def setup
    @instance = TestableAwsInstance.new
    @fake = FakeInstance.new
    @temp_dir = "temp/github_release_test_#{Process.pid}/"
    FileUtils.mkdir_p(@temp_dir)
    @prev_gh = ENV['GH_TOKEN']
    @prev_github = ENV['GITHUB_TOKEN']
    ENV.delete('GH_TOKEN')
    ENV.delete('GITHUB_TOKEN')
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    if @prev_gh.nil?
      ENV.delete('GH_TOKEN')
    else
      ENV['GH_TOKEN'] = @prev_gh
    end
    if @prev_github.nil?
      ENV.delete('GITHUB_TOKEN')
    else
      ENV['GITHUB_TOKEN'] = @prev_github
    end
  end

  def git_app_entry(install: ['npm install'], fast_install: nil)
    machine = {}
    machine['install'] = install unless install.nil?
    machine['fast_install'] = fast_install unless fast_install.nil?
    {
      'deployment' => {
        'service_name' => 'btrz-api-loyalty',
        'source' => {
          'type' => 'git',
          'repo' => 'git@github.com:Betterez/btrz-api-loyalty.git',
          'branch_name' => 'master'
        }
      },
      'machine' => machine
    }
  end

  def test_parse_github_repo_from_ssh_url
    assert_equal(
      { owner: 'Betterez', repo: 'btrz-api-loyalty' },
      GithubReleaseInstaller.parse_github_repo('git@github.com:Betterez/btrz-api-loyalty.git')
    )
  end

  def test_parse_github_repo_rejects_non_github
    assert_raise(ArgumentError) do
      GithubReleaseInstaller.parse_github_repo('git@bitbucket.org:Betterez/btrz-api-loyalty.git')
    end
  end

  def test_validate_tag_accepts_safe_tags
    assert_equal('v1.2.3', GithubReleaseInstaller.validate_tag!('v1.2.3'))
    assert_equal('1.2.3-rc.1', GithubReleaseInstaller.validate_tag!('1.2.3-rc.1'))
  end

  def test_validate_tag_rejects_unsafe_tags
    assert_raise(ArgumentError) { GithubReleaseInstaller.validate_tag!("v1.2.3; rm -rf /") }
    assert_raise(ArgumentError) { GithubReleaseInstaller.validate_tag!('') }
    assert_raise(ArgumentError) { GithubReleaseInstaller.validate_tag!(nil) }
  end

  def test_token_from_env_prefers_gh_token
    ENV['GH_TOKEN'] = 'gh-secret'
    ENV['GITHUB_TOKEN'] = 'github-secret'
    assert_equal('gh-secret', GithubReleaseInstaller.token_from_env!)
  end

  def test_token_from_env_falls_back_to_github_token
    ENV['GITHUB_TOKEN'] = 'github-secret'
    assert_equal('github-secret', GithubReleaseInstaller.token_from_env!)
  end

  def test_token_from_env_raises_when_missing
    assert_raise(ArgumentError) { GithubReleaseInstaller.token_from_env! }
  end

  def test_install_on_instance_uploads_token_and_runs_script
    ENV['GH_TOKEN'] = 'super-secret-token-value'
    GithubReleaseInstaller.install_on_instance(
      @fake,
      service_name: 'btrz-api-loyalty',
      git_repo: 'git@github.com:Betterez/btrz-api-loyalty.git',
      tag: 'v1.2.3',
      build_number: 42
    )

    assert_equal(2, @fake.data_uploads.length)
    assert_equal('super-secret-token-value', @fake.data_uploads[0][0])
    assert_equal(GithubReleaseInstaller::TOKEN_REMOTE_PATH, @fake.data_uploads[0][1])
    assert_equal(GithubReleaseInstaller::SCRIPT_REMOTE_PATH, @fake.data_uploads[1][1])
    script = @fake.data_uploads[1][0]
    assert(script.include?('api.github.com/repos/Betterez/btrz-api-loyalty/releases/tags/v1.2.3'))
    assert(script.include?('application/octet-stream'))
    assert(script.include?('rm -rf /home/bz-app/btrz-api-loyalty'))
    assert(script.include?('chown -R bz-app:bz-app /home/bz-app/btrz-api-loyalty'))
    assert(!script.include?('super-secret-token-value'), 'token must not appear in uploaded script')
    assert(@fake.commands.any? { |c| c.include?('chmod 600') })
    assert(@fake.commands.any? { |c| c == "bash #{GithubReleaseInstaller::SCRIPT_REMOTE_PATH}" })
    assert_equal([42], @fake.build_numbers)
    joined = (@fake.commands + @fake.notifications).join("\n")
    assert(!joined.include?('super-secret-token-value'), 'token must not appear in commands or notifications')
  end

  def test_github_release_skips_clone_and_install
    ENV['GH_TOKEN'] = 'super-secret-token-value'
    @instance.load_single_application_code(
      { build_number: 42, github_release: 'v1.2.3' },
      git_app_entry,
      false,
      @temp_dir
    )

    assert(@instance.commands.none? { |c| c.include?('git clone') })
    assert(@instance.commands.none? { |c| c.include?('git pull') })
    assert(@instance.commands.none? { |c| c.include?('npm install') })
    script = @instance.data_uploads.find { |data, _path| data.to_s.include?('chown -R bz-app:bz-app /home/bz-app/btrz-api-loyalty') }
    refute_nil(script)
    assert_equal(1, @instance.commands.count { |c| c == 'echo 42 | sudo tee /home/bz-app/build_number.txt' })
    assert_equal(2, @instance.data_uploads.length)
    assert_equal('super-secret-token-value', @instance.data_uploads[0][0])
    # Token appears only in the dedicated token upload, not in commands/notifications/script.
    script_body = @instance.data_uploads[1][0].to_s
    assert(!script_body.include?('super-secret-token-value'))
    assert(!(@instance.commands + @instance.notifications).join("\n").include?('super-secret-token-value'))
  end

  def test_github_release_skips_fast_install
    ENV['GH_TOKEN'] = 'super-secret-token-value'
    @instance.load_single_application_code(
      { build_number: 42, github_release: 'v9.9.9' },
      git_app_entry(install: nil, fast_install: ['mix deps.get', 'mix compile']),
      false,
      @temp_dir
    )

    assert(@instance.commands.none? { |c| c.include?('mix deps.get') })
    assert(@instance.commands.none? { |c| c.include?('mix compile') })
  end

  def test_without_github_release_flag_git_clone_still_runs
    @instance.load_single_application_code(
      { build_number: 42 },
      git_app_entry,
      false,
      @temp_dir
    )

    assert(@instance.commands.any? { |c| c.include?('git clone') })
    assert(@instance.commands.any? { |c| c.include?('npm install') })
  end

  def test_github_release_requires_token_before_install
    assert_raise(ArgumentError) do
      @instance.load_single_application_code(
        { build_number: 42, github_release: 'v1.2.3' },
        git_app_entry,
        false,
        @temp_dir
      )
    end
  end

  def test_extract_command_for_zip
    assert_match(/unzip|zipfile/, GithubReleaseInstaller.extract_command_for('app.zip', '/tmp/out'))
  end

  def test_extract_command_for_tar_gz
    assert_match(/tar /, GithubReleaseInstaller.extract_command_for('app.tar.gz', '/tmp/out'))
  end

  def test_extract_command_rejects_other_extensions
    assert_raise(ArgumentError) do
      GithubReleaseInstaller.extract_command_for('app.deb', '/tmp/out')
    end
  end
end
