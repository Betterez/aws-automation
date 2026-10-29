# frozen_string_literal: true

require 'test/unit'
require 'aws-sdk'
require_relative '../betterez/AmiJournalExporter'

class AmiJournalExporterTest < Test::Unit::TestCase
  class FakeInstance
    attr_reader :ssh_calls, :notifications

    def initialize(instance_id, journal)
      @instance_id = instance_id
      @journal = journal
      @ssh_calls = []
      @notifications = []
    end

    def get_aws_id
      @instance_id
    end

    def run_ssh_command(command, loops = 5, command_delay = 5)
      @ssh_calls << { command: command, loops: loops, command_delay: command_delay }
      @journal
    end

    def notify(message)
      @notifications << message
    end
  end

  class FakeS3
    attr_reader :puts, :public_access_block, :encryption, :created_buckets

    def initialize(exists: true, fail_times: 0)
      @exists = exists
      @fail_times = fail_times
      @put_attempts = 0
      @created = false
      @puts = []
      @created_buckets = []
    end

    def head_bucket(bucket:)
      return if @exists || @created

      raise Aws::S3::Errors::NotFound.new(nil, "missing #{bucket}")
    end

    def create_bucket(bucket:)
      @created = true
      @created_buckets << bucket
    end

    def put_public_access_block(params)
      @public_access_block = params
    end

    def put_bucket_encryption(params)
      @encryption = params
    end

    def put_object(params)
      @put_attempts += 1
      raise 's3 down' if @put_attempts <= @fail_times

      @puts << params
    end
  end

  def setup
    AmiJournalExporter.reset_exported!
    @setup = {
      environment: 'sandbox',
      build_number: '84',
      'deployment' => { 'service_name' => 'btrz-api-gps' }
    }
    @journal = "service started\nmongodb://appuser:s3cret@mongo.internal:27017/gps\n"
  end

  def test_uploads_sanitized_current_boot_journal
    client = FakeS3.new
    instance = FakeInstance.new('i-abc123', @journal)
    error = 'healthcheck failed mongodb://appuser:s3cret@mongo.internal/gps'

    key = AmiJournalExporter.export(instance, @setup, error, s3_client: client)

    assert_match(%r{\Ajournals/sandbox/btrz-api-gps/84/i-abc123/\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}\.log\z}, key)
    assert_equal(1, client.puts.length)
    params = client.puts.first
    assert_equal(AmiJournalExporter::BUCKET, params[:bucket])
    assert_equal(key, params[:key])
    assert_equal('AES256', params[:server_side_encryption])
    assert_equal(false, params.key?(:acl))
    assert_no_match(/s3cret/, params[:body])
    assert_no_match(/appuser/, params[:body])
    assert_match(/instance_id: i-abc123/, params[:body])
    assert_match(/service: btrz-api-gps/, params[:body])
    assert_match(/environment: sandbox/, params[:body])
    assert_match(/build_number: 84/, params[:body])
    assert_match(/error: healthcheck failed mongodb:\/\/\[REDACTED\]@mongo\.internal\/gps/, params[:body])
    assert_match(%r{mongodb://\[REDACTED\]@mongo\.internal:27017/gps}, params[:body])
    assert_equal('sudo journalctl -b -u btrz-api-gps.service --no-pager -o short-iso', instance.ssh_calls.first[:command])
    assert_equal(params[:body], instance.notifications.first)
    assert_no_match(/s3cret/, instance.notifications.first)
    assert_equal(2, instance.ssh_calls.first[:loops])
    assert_empty(client.created_buckets)
  end

  def test_creates_private_encrypted_bucket_when_missing
    client = FakeS3.new(exists: false)
    instance = FakeInstance.new('i-new', 'service started')

    AmiJournalExporter.export(instance, @setup, nil, s3_client: client)

    assert_equal([AmiJournalExporter::BUCKET], client.created_buckets)
    config = client.public_access_block[:public_access_block_configuration]
    assert_equal(true, config[:block_public_acls])
    assert_equal(true, config[:ignore_public_acls])
    assert_equal(true, config[:block_public_policy])
    assert_equal(true, config[:restrict_public_buckets])
    rule = client.encryption[:server_side_encryption_configuration][:rules].first
    assert_equal('AES256', rule[:apply_server_side_encryption_by_default][:sse_algorithm])
  end

  def test_exports_each_instance_once
    client = FakeS3.new
    instance = FakeInstance.new('i-once', @journal)

    first = AmiJournalExporter.export(instance, @setup, 'healthcheck failed', s3_client: client)
    second = AmiJournalExporter.export(instance, @setup, 'healthcheck failed', s3_client: client)

    assert_equal(first, second)
    assert_equal(1, client.puts.length)
    assert_equal(1, instance.ssh_calls.length)
  end

  def test_s3_failure_does_not_raise_and_can_retry
    client = FakeS3.new(fail_times: 1)
    instance = FakeInstance.new('i-retry', @journal)

    failed = AmiJournalExporter.export(instance, @setup, 'healthcheck failed', s3_client: client)
    uploaded = AmiJournalExporter.export(instance, @setup, 'healthcheck failed', s3_client: client)

    assert_nil(failed)
    assert_match(%r{\Ajournals/sandbox/btrz-api-gps/84/i-retry/}, uploaded)
    assert_equal(1, client.puts.length)
    assert_match(/failed to export ami journal/, instance.notifications.join)
  end

  def test_empty_journal_is_still_uploaded
    client = FakeS3.new
    instance = FakeInstance.new('i-empty', '  ')

    AmiJournalExporter.export(instance, @setup, 'ssh produced no journal', s3_client: client)

    assert_match(/journalctl returned no output/, client.puts.first[:body])
  end
end
