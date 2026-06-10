# frozen_string_literal: true

require 'test/unit'
require 'fileutils'
require 'time'
require_relative '../betterez/GoogleCloudStorage'

class GoogleCloudStorageTest < Test::Unit::TestCase
  def teardown
    GoogleCloudStorage.instance_variable_set(:@storage, nil)
  end

  def with_storage_mock(storage_mock)
    original = GoogleCloudStorage.method(:storage)
    GoogleCloudStorage.define_singleton_method(:storage) { storage_mock }
    yield
  ensure
    GoogleCloudStorage.define_singleton_method(:storage, original)
    GoogleCloudStorage.instance_variable_set(:@storage, nil)
  end

  def file_entry(name, updated_at, content = 'tar-data')
    file_mock = Object.new
    file_mock.define_singleton_method(:name) { name }
    file_mock.define_singleton_method(:updated) { updated_at }
    file_mock.define_singleton_method(:download) do |dest|
      FileUtils.mkdir_p(File.dirname(dest))
      File.write(dest, content)
    end
    file_mock
  end

  def bucket_with_files(files_by_name)
    bucket_mock = Object.new
    bucket_mock.instance_variable_set(:@files, files_by_name)
    def bucket_mock.file(name)
      @files[name]
    end
    def bucket_mock.files(prefix:)
      @files.values.select { |f| f.name.start_with?(prefix) }
    end
    bucket_mock
  end

  def test_download_file_of_bucket_writes_file_and_returns_path
    file_mock = file_entry('path/image.tar', Time.now)

    bucket_mock = bucket_with_files({ 'path/image.tar' => file_mock })
    storage_mock = Object.new
    storage_mock.instance_variable_set(:@buckets, { 'artifacts' => bucket_mock })
    def storage_mock.bucket(name)
      @buckets[name]
    end

    dir = nil
    with_storage_mock(storage_mock) do
      dir = "temp/test_gcs_#{Process.pid}/"
      FileUtils.rm_rf(dir)
      path = GoogleCloudStorage.download_file_of_bucket('artifacts', 'path/image.tar', dir)

      assert_equal(File.join(dir, 'path/image.tar'), path)
      assert_equal('tar-data', File.read(path))
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def test_download_latest_file_of_bucket_picks_newest_tar_and_renames_to_image_tar
    older = file_entry('builds/old.tar', Time.now - 3600, 'old')
    newer = file_entry('builds/new_build.tar.gz', Time.now, 'new')

    bucket_mock = bucket_with_files(
      'builds/old.tar' => older,
      'builds/new_build.tar.gz' => newer,
      'builds/readme.txt' => file_entry('builds/readme.txt', Time.now)
    )
    storage_mock = Object.new
    storage_mock.instance_variable_set(:@buckets, { 'artifacts' => bucket_mock })
    def storage_mock.bucket(name)
      @buckets[name]
    end

    dir = nil
    with_storage_mock(storage_mock) do
      dir = "temp/test_gcs_latest_#{Process.pid}/"
      FileUtils.rm_rf(dir)
      path = GoogleCloudStorage.download_latest_file_of_bucket('artifacts', 'builds/', dir)

      assert_equal(File.join(dir, 'image.tar'), path)
      assert_equal('new', File.read(path))
      assert(!File.exist?(File.join(dir, 'builds/new_build.tar.gz')))
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def test_download_latest_file_of_bucket_raises_when_no_tar_files
    bucket_mock = bucket_with_files(
      'builds/readme.txt' => file_entry('builds/readme.txt', Time.now)
    )
    storage_mock = Object.new
    storage_mock.instance_variable_set(:@buckets, { 'artifacts' => bucket_mock })
    def storage_mock.bucket(name)
      @buckets[name]
    end

    with_storage_mock(storage_mock) do
      assert_raise(RuntimeError) do
        GoogleCloudStorage.download_latest_file_of_bucket('artifacts', 'builds/', 'temp/')
      end
    end
  end

  def test_download_file_of_bucket_raises_when_bucket_missing
    storage_mock = Object.new
    def storage_mock.bucket(_name)
      nil
    end

    with_storage_mock(storage_mock) do
      assert_raise(RuntimeError) do
        GoogleCloudStorage.download_file_of_bucket('missing', 'file.tar', 'temp/')
      end
    end
  end
end
