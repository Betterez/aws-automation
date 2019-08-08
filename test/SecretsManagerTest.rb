#!/usr/bin/ruby
# frozen_string_literal: true

require 'test/unit'
require_relative '../betterez/SecretsManager'

class SecretsManagerTest < Test::Unit::TestCase
  def setup
    @manager = SecretsManager.new
  end

  def test_set_engine
    @manager.engine="vault"
    assert_equal(@manager.engine, 'vault')
  end

  def test_default_engine
    assert_equal(@manager.engine, 'aws')
  end

  def test_initial_environemnt
    assert_equal(@manager.environment, 'production')
  end

  def test_initial_repository
    assert_nil(@manager.repository)
  end

  def test_setting_repository
    @manager.repository = 'app'
    assert_equal(@manager.repository, 'app', 'repository should be assignable')
  end

  def test_get_json_throws_without_repo
    assert_throw(SecretsManager::NO_REPO) do
      @manager.get_secrets_hash
    end
  end

  def test_get_secrets_hash
    omit
    @manager.repository = 'btrz-api-loyalty'
    data, code = @manager.get_secrets_hash
    assert_equal(code, 200)
    assert_equal(data['username'], 'loyalty_user')
  end

  def test_secret_exists
    assert(@manager.is_secret_exists?("testtest"))
  end

  def test_secret_creation_requires
    assert_false(@manager.need_to_create_secret?("testtest"),"the secret suppose to be there")
  end

  def test_set_variable
    @manager.repository = 'test'
    @manager.environment = 'test'
    code = @manager.set_secret_value(name: 'mytest', secret: '123456789')
    assert(code > 200 || code < 400)
    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets.has_key?("mytest"))
  end

  def test_delete_repo_data
    test_repo_name="test"
    test_environment="test"
    @manager.repository=test_repo_name
    @manager.environment=test_environment

    names=@manager.get_all_secrets_names



  end
end
