require 'aws-sdk-secretsmanager'
require 'base64'
class SecretsManager
    NO_REPO=:"No repository"
    NO_ENV=:"No environment"
    def initialize
        @default_engine="aws"
        @environment="production"
        region_name = "us-east-1"
        @client = Aws::SecretsManager::Client.new(region: region_name)
    end

    def get_engine
        @default_engine
    end

    def get_json
        throw  SecretsManager::NO_ENV if  @environment.nil?
        throw SecretsManager::NO_REPO if @repository.nil?
        secret_name = "postgres"
        begin
          get_secret_value_response = @client.get_secret_value(secret_id: secret_name)
        rescue
          return nil,500
        end
        if get_secret_value_response.secret_string
          secret = get_secret_value_response.secret_string
          json_secret=JSON.parse secret
        end
        return json_secret,200
    end
    attr_accessor :environment
    attr_accessor :repository

    # private:
end
