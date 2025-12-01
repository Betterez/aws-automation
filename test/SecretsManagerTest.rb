#!/usr/bin/ruby
# frozen_string_literal: true
# these tests will create a secret in AWS on each run and this costs money
require 'test/unit'
require_relative '../betterez/SecretsManager'

class SecretsManagerTest < Test::Unit::TestCase  
  @@random_repo = Helpers.create_random_string(5)

  def setup
    @manager = SecretsManager.new    
  end

  def test_set_engine
    @manager.engine="sm"
    assert_equal(@manager.engine, 'sm')
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

  def test_1_convert_to_env_file_format
    @manager.environment = 'testing'
    @manager.repository = 'test-' + @@random_repo

    key_name = 'mytest'
    key_value = Helpers.create_random_string(12)
    assert(@manager.need_to_create_secret?(@manager.compose_secret_name),
      "need to create #{@manager.compose_secret_name}")
    sleep 1  
    code = @manager.set_secret_value(name: key_name, secret: key_value)
    sleep 1
    assert(code > 200 || code < 400)
    repo_secrets,code=@manager.get_secrets_hash
    sleep 1
    @manager.convert_to_env_file_format(repo_secrets)
  end

  def test_2_create_new_secret
    @manager.environment = 'testing'
    @manager.repository = 'test-' + @@random_repo

    secret_value_1 = "value 1"
    secret_value_2 = "value 2"
    secret_value_3 = "value 3"
    create_set = {
      secret1: secret_value_1, 
      secret2: secret_value_2,
      secret3: secret_value_3
    }
    code = @manager.set_secret_value(create_set, true)
    sleep 1
    assert(code > 200 || code < 400)

    repo_secrets,code=@manager.get_secrets_hash
    sleep 1
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?("secret1"))
    assert(repo_secrets.key?("secret2"))
    assert(repo_secrets.key?("secret3"))
    assert(repo_secrets["secret1"] == secret_value_1,"secret1 should be #{secret_value_1}, but it is #{repo_secrets["secret1"]}")
    assert(repo_secrets["secret2"] == secret_value_2,"secret2 should be #{secret_value_2}, but it is #{repo_secrets["secret2"]}")
    assert(repo_secrets["secret3"] == secret_value_3,"secret3 should be #{secret_value_3}, but it is #{repo_secrets["secret3"]}")
  end

  def test_3_update_secret
    @manager.environment = 'testing'
    @manager.repository = 'test-' + @@random_repo 

    new_secret_value_2 = "updated 2"
    new_secret_value_3 = "updated 3"

    update_set = {
      secret2: new_secret_value_2,
      secret3: new_secret_value_3
    }

    code = @manager.set_secret_value(update_set, true)
    sleep 1
    assert(code > 200 || code < 400)

    repo_secrets,code=@manager.get_secrets_hash
    sleep 1
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?("secret1"))
    assert(repo_secrets.key?("secret2"))
    assert(repo_secrets.key?("secret3"))
    assert(repo_secrets["secret1"] == "value 1","secret1 should be value 1, but it is #{repo_secrets["secret1"]}")
    assert(repo_secrets["secret2"] == new_secret_value_2,"secret2 should be #{new_secret_value_2}, but it is #{repo_secrets["secret2"]}")
    assert(repo_secrets["secret3"] == new_secret_value_3,"secret3 should be #{new_secret_value_3}, but it is #{repo_secrets["secret3"]}")
  end

  def test_4_remove_secret_key
    @manager.environment = "testing"
    @manager.repository = 'test-' + @@random_repo

    code = @manager.delete_secret_key("secret2")
    sleep 1
    assert(code > 200 || code < 400)

    repo_secrets,code=@manager.get_secrets_hash
    sleep 1
    assert(code > 200 || code < 400)
    assert(repo_secrets.key?("secret1"))
    assert(repo_secrets.key?("secret2") == false)
    assert(repo_secrets.key?("secret3"))
  end

  def test_5_handles_values_with_spaces
    @manager.environment = 'testing'
    @manager.repository = 'test-' + @@random_repo
    key_name = 'mytest2'
    key_value = "asdf asdf asdf"
    sleep 1  
    code = @manager.set_secret_value(name: key_name, secret: key_value)
    sleep 1
    assert(code > 200 || code < 400)
    repo_secrets,code=@manager.get_secrets_hash
    sleep 1
    vault_data = @manager.convert_to_env_file_format(repo_secrets)
    configuration_file_content = <<~EOF
    TEST=value1
    EOF
    if !vault_data.nil? && vault_data != ''
      pairs_vault_data = vault_data.split(/\s(?=[A-Z0-9_]+=)/)
      pairs_vault_data.each do |value|
        configuration_file_content += "#{value}\n"
      end
    end
    content_lines = configuration_file_content.strip.split("\n")
    content_lines.each do |line|
      assert_match(/^[A-Z0-9_]+=.+$/, line, "Line is not in KEY=value")
    end
  end

  def test_6_delete_repo_data
    @manager.environment = "testing"
    @manager.repository = 'test-' + @@random_repo

    @manager.remove_repo_secrets
    sleep 1
    names=@manager.get_all_secrets_names
    assert_false(names.include?(@manager.compose_secret_name),"after deletion shouldn't see this repo")
  end
end
