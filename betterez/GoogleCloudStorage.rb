# frozen_string_literal: true

require 'fileutils'
require_relative 'Helpers'

module GoogleCloudStorage
  DOCKER_IMAGE_FILENAME = 'image.tar'
  TAR_PATTERN = /\.tar(\.gz)?\z/i

  module_function

  def get_account
    storage_account_data = Helpers.loadJSONData("settings/gcs-auth.json")
    raise 'gcs auth file does not exist!' unless File.exist?("settings/gcs-auth.json")
    raise "can't load account data" if storage_account_data["gcs"].nil?
    storage_account_data
  end

  def storage
    require 'google/cloud/storage'
    @account ||= get_account
    @storage ||= Google::Cloud::Storage.new(
      credentials: @account["gcs"]["credentials_path"],
      project_id: @account["gcs"]["project_id"],
    )
    raise "can't load storage" if @storage.nil?
  end

  def get_bucket(bucket_name)
    storage.bucket bucket_name
  end

  # Downloads object file_name from bucket_name into output_dir (preserving object path segments).
  # Returns the local path to the downloaded file.
  def download_file_of_bucket(bucket_name, file_name, output_dir)
    bucket = get_bucket(bucket_name)
    raise "Bucket not found: #{bucket_name}" unless bucket

    file = bucket.file file_name
    raise "File not found: #{file_name} in #{bucket_name}" unless file

    destination = File.join(output_dir, file_name)
    FileUtils.mkdir_p(File.dirname(destination))
    file.download(destination)
    destination
  end

  # Lists .tar/.tar.gz objects under dir_name, picks the most recently updated,
  # downloads it, and renames to DOCKER_IMAGE_FILENAME in output_dir.
  def download_latest_file_of_bucket(bucket_name, dir_name, output_dir)
    bucket = get_bucket(bucket_name)
    raise "Bucket not found: #{bucket_name}" unless bucket

    files = bucket.files(prefix: dir_name).select do |f|
      f.name.match?(TAR_PATTERN) && !f.name.end_with?('/')
    end

    latest_file = files.max_by(&:updated)
    raise "No .tar(.gz) files found in #{dir_name} in #{bucket_name}" if latest_file.nil?

    downloaded_path = download_file_of_bucket(bucket_name, latest_file.name, output_dir)
    fixed_path = File.join(output_dir, DOCKER_IMAGE_FILENAME)
    FileUtils.mv(downloaded_path, fixed_path) unless downloaded_path == fixed_path
    fixed_path
  end
end