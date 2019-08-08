# frozen_string_literal: true

require 'aws-sdk-secretsmanager'
require 'base64'
class SecretsManager
  NO_REPO = :"No repository"
  NO_ENV = :"No environment"
  def initialize
    @default_engine = 'aws'
    @environment = 'production'
    region_name = 'us-east-1'
    @client = Aws::SecretsManager::Client.new(region: region_name)
  end

  def get_engine
    @default_engine
  end

  def get_json
    throw SecretsManager::NO_ENV if @environment.nil?
    throw SecretsManager::NO_REPO if @repository.nil?
    secret_name = compose_secret_name
    begin
      get_secret_value_response = @client.get_secret_value(secret_id: secret_name)
    rescue StandardError => e
      return nil, 500
    end
    if get_secret_value_response.secret_string
      secret = get_secret_value_response.secret_string
      json_secret = JSON.parse secret
    end
    [json_secret, 200]
  end


  def set_secret_value(_secret_hash)
    resp=@client.create_secret({
      client_request_token: "token1token1token1token1token1token1token1",
      name: compose_secret_name,
      secret_binary:nil,
      secret_string: _secret_hash[:value]
      })
    200
  end

  def get_all_secrets_names
    secrets_name_result=[]
    resp=@client.list_secrets()
    resp[:secret_list].each do |item|
      secrets_name_result.push(item[:name])
    end
    secrets_name_result
  end

  def need_to_create_secret(secret_name)
    names=get_all_secrets_names
    return !names.include?(secret_name)
  end

  attr_accessor :environment
  attr_accessor :repository

  private

  def compose_secret_name
    @repository + @environment
  end


end
