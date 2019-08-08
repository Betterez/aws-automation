require 'aws-sdk-secretsmanager'
require 'base64'
class SecretsManager
    NO_REPO=:"No repository"
    NO_ENV=:"No environment"
    def initialize
        @default_engine="aws"
        @environment="production"
        @client = Aws::SecretsManager::Client.new(region: region_name)
    end

    def get_engine
        @default_engine
    end

    def get_json
        throw  SecretsManager::NO_ENV if  @environment.nil?
        throw SecretsManager::NO_REPO if @repository.nil?
        get_secret_value_response = client.get_secret_value(secret_id: secret_name)
        return nil,200
    end
    attr_accessor :environment
    attr_accessor :repository

    private:
end
