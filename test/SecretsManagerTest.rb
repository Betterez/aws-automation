#!/usr/bin/ruby
# frozen_string_literal: true

require 'test/unit'
require_relative '../betterez/SecretsManager'

class SecretsManagerTest < Test::Unit::TestCase
  def setup
    @manager = SecretsManager.new
  end

  # def test_set_engine
  #   @manager.engine="vault"
  #   assert_equal(@manager.engine, 'vault')
  # end
  #
  # def test_default_engine
  #   assert_equal(@manager.engine, 'aws')
  # end
  #
  # def test_initial_environemnt
  #   assert_equal(@manager.environment, 'production')
  # end
  #
  # def test_initial_repository
  #   assert_nil(@manager.repository)
  # end
  #
  # def test_setting_repository
  #   @manager.repository = 'app'
  #   assert_equal(@manager.repository, 'app', 'repository should be assignable')
  # end
  #
  # def test_get_json_throws_without_repo
  #   assert_throw(SecretsManager::NO_REPO) do
  #     @manager.get_secrets_hash
  #   end
  # end
  #
  # def test_get_secrets_hash
  #   omit
  #   @manager.repository = 'btrz-api-loyalty'
  #   data, code = @manager.get_secrets_hash
  #   assert_equal(code, 200)
  #   assert_equal(data['username'], 'loyalty_user')
  # end
  #
  # def test_secret_exists
  #   omit
  #   assert(@manager.is_secret_exists?("testtest"))
  # end
  #
  # def test_secret_creation_requires
  #   omit
  #   assert_false(@manager.need_to_create_secret?("testtest"),"the secret suppose to be there")
  # end

  def test_set_variable
    @manager.repository = 'test'+Helpers.create_random_string(5)
    @manager.environment = 'test'
    key_name='mytest'
    key_value=Helpers.create_random_string(12)

    code = @manager.set_secret_value(name: key_name, secret: key_value)
    assert(code > 200 || code < 400)
    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets.has_key?(key_name))
    assert(repo_secrets[key_name]==key_value,"#{key_name} should be #{key_value}, but it is #{repo_secrets[key_name]}")
    @manager.remove_repo_secrets
  end

  def test_delete_repo_data
    test_repo_name="test"+Helpers.create_random_string(5)
    test_environment="test"
    @manager.repository=test_repo_name
    @manager.environment=test_environment
    @manager.set_secret_value({name: "test", secret: "some secret"})
    sleep(1)
    names=@manager.get_all_secrets_names
    assert(names.include?(test_repo_name),"new repo #{test_repo_name} should exists")
    code=@manager.remove_repo_secrets
    names=@manager.get_all_secrets_names
    assert_false(names.include?(test_repo_name),"after deletion shouldn't see this repo")
  end

end
