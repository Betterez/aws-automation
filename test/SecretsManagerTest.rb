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
    assert_equal(@manager.environment, 'sandbox')
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

  def test_set_variable
    @manager.repository = 'test'+Helpers.create_random_string(5)
    @manager.environment = 'test'
    key_name = 'mytest'
    key_value = Helpers.create_random_string(12)

    assert(@manager.need_to_create_secret?(@manager.compose_secret_name),
      "need to create #{@manager.compose_secret_name}")
    code = @manager.set_secret_value(name: key_name, secret: key_value)
    assert(@manager.is_secret_exists?(@manager.compose_secret_name),"secret needs to be here")
    assert_false(@manager.need_to_create_secret?(@manager.compose_secret_name),"no need to create existing secret")
    assert(code > 200 || code < 400)
    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?(key_name))
    assert(repo_secrets[key_name] == key_value,"#{key_name} should be #{key_value}, but it is #{repo_secrets[key_name]}")
    key_value = Helpers.create_random_string(12)
    code = @manager.set_secret_value(name: key_name, secret: key_value)
    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets[key_name] == key_value,"#{key_name} should be #{key_value}, but it is #{repo_secrets[key_name]}")
    @manager.remove_repo_secrets
  end

  def test_convert_to_env_file_format
    @manager.environment = 'test'
    @manager.repository = 'test'+Helpers.create_random_string(5)
    key_name = 'mytest'
    key_value = Helpers.create_random_string(12)
    assert(@manager.need_to_create_secret?(@manager.compose_secret_name),
      "need to create #{@manager.compose_secret_name}")
    code = @manager.set_secret_value(name: key_name, secret: key_value)
    assert(code > 200 || code < 400)
    repo_secrets,code=@manager.get_secrets_hash
    puts repo_secrets
    env_data = @manager.convert_to_env_file_format(repo_secrets)
    puts env_data
  end

  def test_create_new_secret
    @manager.repository = 'testing-repository'
    @manager.environment = 'testing'
    secret_value_1 = "value 1"
    secret_value_2 = "value 2"
    secret_value_3 = "value 3"
    create_set = {
      secret1: secret_value_1, 
      secret2: secret_value_2,
      secret3: secret_value_3
    }
    code = @manager.set_secret_value(create_set, true)
    assert(code > 200 || code < 400)

    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?("secret1"))
    assert(repo_secrets.key?("secret2"))
    assert(repo_secrets.key?("secret3"))
    assert(repo_secrets["secret1"] == secret_value_1,"secret1 should be #{secret_value_1}, but it is #{repo_secrets["secret1"]}")
    assert(repo_secrets["secret2"] == secret_value_2,"secret2 should be #{secret_value_2}, but it is #{repo_secrets["secret2"]}")
    assert(repo_secrets["secret3"] == secret_value_3,"secret3 should be #{secret_value_3}, but it is #{repo_secrets["secret3"]}")
  end

  def test_update_secret
    @manager.repository = 'testing-repository'
    @manager.environment = 'testing'

    new_secret_value_2 = "updated 2"
    new_secret_value_3 = "updated 3"

    update_set = {
      secret2: new_secret_value_2,
      secret3: new_secret_value_3
    }

    code = @manager.set_secret_value(update_set, true)
    assert(code > 200 || code < 400)

    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?("secret1"))
    assert(repo_secrets.key?("secret2"))
    assert(repo_secrets.key?("secret3"))
    assert(repo_secrets["secret1"] == "value 1","secret1 should be value 1, but it is #{repo_secrets["secret1"]}")
    assert(repo_secrets["secret2"] == new_secret_value_2,"secret2 should be #{new_secret_value_2}, but it is #{repo_secrets["secret2"]}")
    assert(repo_secrets["secret3"] == new_secret_value_3,"secret3 should be #{new_secret_value_3}, but it is #{repo_secrets["secret3"]}")
  end

  def test_remove_secret_key
    @manager.repository = "testing-repository"
    @manager.environment = "testing"

    code = @manager.delete_secret_key("secret2")
    assert(code > 200 || code < 400)

    repo_secrets,code=@manager.get_secrets_hash
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?("secret1"))
    assert(repo_secrets.key?("secret2") == false)
    assert(repo_secrets.key?("secret3"))
  end

  def test_delete_repo_data
    omit
    test_repo_name="test"+Helpers.create_random_string(5)
    test_environment="test"

    @manager.repository=test_repo_name
    @manager.environment=test_environment
    @manager.set_secret_value({name: "test", secret: "some secret"})
    names=@manager.get_all_secrets_names
    assert(names.include?(@manager.compose_secret_name),"new repo #{@manager.compose_secret_name} should exists")
    code = @manager.remove_repo_secrets
    names=@manager.get_all_secrets_names
    assert_false(names.include?(@manager.compose_secret_name),"after deletion shouldn't see this repo")
  end

  def test_delete_test_secrets
    omit
    names=@manager.get_all_secrets_names
    names.each do |name|
      if name.index("test")==0
        puts "removing #{name}"
        puts @manager.remove_repo_secrets_by_name name
      end
    end
    
  end
end
