# frozen_string_literal: true

require_relative 'Helpers'
require_relative 'JournalSanitizer'

class AmiJournalExporter
  BUCKET = 'btrz-ami-builder-journals'
  REGION = 'us-east-1'
  JOURNAL_COMMAND = 'sudo journalctl -b --no-pager -o short-iso'
  SSH_ATTEMPTS = 2

  @mutex = Mutex.new
  @exported = {}

  def self.export(instance, service_setup_data, error = nil, s3_client: nil)
    instance_id = instance.get_aws_id
    @mutex.synchronize do
      return @exported[instance_id] if @exported.key?(instance_id)

      key = upload(instance, service_setup_data, error, s3_client)
      @exported[instance_id] = key if key
      key
    end
  rescue StandardError => export_error
    notify_failure(instance, export_error)
    nil
  end

  def self.reset_exported!
    @mutex.synchronize { @exported = {} }
  end

  def self.upload(instance, service_setup_data, error, s3_client)
    client = s3_client || Helpers.create_aws_S3_client(REGION)
    ensure_private_bucket(client)
    key = object_key(instance, service_setup_data)
    client.put_object(
      bucket: BUCKET,
      key: key,
      body: journal_body(instance, service_setup_data, error),
      server_side_encryption: 'AES256'
    )
    key
  end

  def self.ensure_private_bucket(client)
    client.head_bucket(bucket: BUCKET)
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
    client.create_bucket(bucket: BUCKET)
    client.put_public_access_block(
      bucket: BUCKET,
      public_access_block_configuration: {
        block_public_acls: true,
        ignore_public_acls: true,
        block_public_policy: true,
        restrict_public_buckets: true
      }
    )
    client.put_bucket_encryption(
      bucket: BUCKET,
      server_side_encryption_configuration: {
        rules: [
          {
            apply_server_side_encryption_by_default: {
              sse_algorithm: 'AES256'
            }
          }
        ]
      }
    )
  end

  def self.object_key(instance, service_setup_data)
    [
      'journals',
      path_segment(service_setup_data[:environment]),
      path_segment(service_name(service_setup_data)),
      path_segment(service_setup_data[:build_number]),
      path_segment(instance.get_aws_id),
      "#{Helpers.create_time_date_string}.log"
    ].join('/')
  end

  def self.journal_body(instance, service_setup_data, error)
    journal = instance.run_ssh_command(JOURNAL_COMMAND, SSH_ATTEMPTS, 2).to_s
    journal = 'journalctl returned no output' if journal.strip.empty?
    header = [
      "instance_id: #{instance.get_aws_id}",
      "service: #{service_name(service_setup_data)}",
      "environment: #{service_setup_data[:environment]}",
      "build_number: #{service_setup_data[:build_number]}",
      "error: #{error}"
    ].join("\n")
    JournalSanitizer.sanitize("#{header}\n\n#{journal}\n")
  end

  def self.service_name(service_setup_data)
    deployment = service_setup_data['deployment'] || service_setup_data[:deployment] || {}
    deployment['service_name'] || deployment[:service_name] || 'unknown'
  end

  def self.path_segment(value)
    segment = value.to_s.gsub(/[^A-Za-z0-9._-]/, '_')
    segment.empty? ? 'unknown' : segment
  end

  def self.notify_failure(instance, error)
    message = "failed to export ami journal: #{error.message}"
    instance.notify(message) if instance.respond_to?(:notify)
  end

  private_class_method :upload, :ensure_private_bucket, :object_key, :journal_body,
                       :service_name, :path_segment, :notify_failure
end
