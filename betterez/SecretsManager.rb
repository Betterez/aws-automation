# frozen_string_literal: true

require 'aws-sdk-secretsmanager'
require 'base64'
require_relative 'Helpers'
class SecretsManager
  NO_REPO = :"No repository"
  NO_ENV = :"No environment"
  def initialize
    @engine = 'aws'
    @environment = 'sandbox'
    region_name = 'us-east-1'
    @client = Aws::SecretsManager::Client.new(region: region_name)
  end

  def compose_secret_name
    "#{@environment}/#{@repository}"
  end

  def get_secrets_hash
    throw SecretsManager::NO_ENV if @environment.nil?
    throw SecretsManager::NO_REPO if @repository.nil?
    secret_name = compose_secret_name
    begin
      get_secret_value_response = @client.get_secret_value(secret_id: secret_name)
    rescue StandardError => e
      puts "Error getting the secrets: #{e}"
      return nil, 500
    end
    if get_secret_value_response.secret_string
      secret = get_secret_value_response.secret_string
      secrets_hash = JSON.parse secret
    end
    [secrets_hash, 200]
  end

  def remove_repo_secrets
    remove_repo_secrets_by_name compose_secret_name
  end

  def remove_repo_secrets_by_name(name)
    @client.delete_secret(
      recovery_window_in_days: 7,
      secret_id: name
    )
  end

  def get_new_secrets(secrets_hash, new_secrets_hash)
    new_secrets_hash.keys.each do |key|
      secrets_hash[key] = new_secrets_hash[key]
    end
    secrets_hash
  end

  def set_secret_value(secrets_hash, append = true)
    if need_to_create_secret?(compose_secret_name)
      @client.create_secret(
        client_request_token: Helpers.create_random_string(32),
        name: compose_secret_name,
        secret_binary: nil,
        secret_string: secrets_hash.to_json
      )
    else
      updated_secrets_hash = secrets_hash
      if append
        existing_secrets_hash, code = get_secrets_hash
        if code > 299
          return 500
        end

        updated_secrets_hash = get_new_secrets(existing_secrets_hash, secrets_hash)
      end

      @client.put_secret_value(
        client_request_token: Helpers.create_random_string(32),
        secret_id: compose_secret_name,
        secret_string: updated_secrets_hash.to_json)      
    end
    200
  end

  def delete_secret_key(key_name)
    existing_secrets, code = get_secrets_hash
    if code > 299
      return 500
    end
    
    updated_secrets={}
    existing_secrets.each do |key, value|
      next if key==key_name
      updated_secrets[key]=value
    end

    code=set_secret_value(updated_secrets,false)
    code
  end

  def get_all_secrets_names
    secrets_name_result = []
    resp = @client.list_secrets({
      max_results: 100,
    })
    resp[:secret_list].each do |item|
      secrets_name_result.push(item[:name])
    end
    secrets_name_result
  end

  def is_secret_exists?(secret_name)
    names = get_all_secrets_names
    names.include?(secret_name)
  end

  def need_to_create_secret?(secret_name)
    !is_secret_exists?(secret_name)
  end

  def convert_to_env_file_format(hash_data)
    env_data = ''
    hash_data.keys.each do |key|
        if !hash_data[key].nil? && hash_data[key].strip != ''
          env_data += key.upcase + '=' + hash_data[key] + ' '
        end
    end
    env_data
  end

  attr_accessor :environment
  attr_accessor :engine
  attr_accessor :repository
end
